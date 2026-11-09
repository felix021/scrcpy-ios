// SPDX-License-Identifier: GPL-3.0-only
// Memory-BIO adapter for the public C interface in AdbCrypto.h.
// Protocol operations are ported from AOSP adb, android-14.0.0_r1:
// pairing_auth/{pairing_auth,aes_128_gcm}.cpp, crypto/x509_generator.cpp,
// and tls/tls_connection.cpp. See THIRD_PARTY_NOTICES.md.
/*
 * Copyright (C) 2019, 2020 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "AdbCrypto.h"
#include <array>
#include <climits>
#include <cstdio>
#include <cstring>
#include <limits>
#include <memory>
#include <new>
#include <openssl/aead.h>
#include <openssl/bytestring.h>
#include <openssl/curve25519.h>
#include <openssl/err.h>
#include <openssl/evp.h>
#include <openssl/hkdf.h>
#include <openssl/mem.h>
#include <openssl/rsa.h>
#include <openssl/ssl.h>
#include <openssl/x509.h>

struct sc_tls {
    bssl::UniquePtr<SSL> connection;
};

struct sc_pair {
    bssl::UniquePtr<SPAKE2_CTX> exchange;
    bssl::ScopedEVP_AEAD_CTX cipher;
    std::array<uint8_t, SPAKE2_MAX_MSG_SIZE> public_message{};
    size_t public_size = 0;
    uint64_t sent = 0;
    uint64_t received = 0;
    bool cipher_ready = false;
};

namespace {

// Android uses a paired RSA key, rather than a public certificate authority.
// Pairing authenticates the TLS exporter with the password via SPAKE2.
ssl_verify_result_t AcceptAdbCertificate(SSL *, uint8_t *) {
    return ssl_verify_ok;
}

bssl::UniquePtr<X509> ClientCertificate(EVP_PKEY *key) {
    bssl::UniquePtr<X509> certificate(X509_new());
    if (!certificate) return nullptr;
    X509_NAME *subject = X509_get_subject_name(certificate.get());
    const unsigned char common_name[] = "Remote scrcpy ADB client";
    if (!X509_set_version(certificate.get(), 2) ||
        !ASN1_INTEGER_set(X509_get_serialNumber(certificate.get()), 1) ||
        !X509_gmtime_adj(X509_getm_notBefore(certificate.get()), -60) ||
        !X509_gmtime_adj(X509_getm_notAfter(certificate.get()), 315360000L) ||
        !X509_set_pubkey(certificate.get(), key) ||
        !X509_NAME_add_entry_by_txt(subject, "CN", MBSTRING_ASC, common_name, -1, -1, 0) ||
        !X509_set_issuer_name(certificate.get(), subject) ||
        !X509_sign(certificate.get(), key, EVP_sha256())) return nullptr;
    return certificate;
}

int RecordResult(sc_tls *tls, int status) {
    if (status > 0) return status;
    switch (SSL_get_error(tls->connection.get(), status)) {
        case SSL_ERROR_WANT_READ:
        case SSL_ERROR_WANT_WRITE: return -2;
        case SSL_ERROR_ZERO_RETURN: return 0;
        default: return -1;
    }
}

int PairRecord(sc_pair *pair, bool encrypt, const uint8_t *input, size_t length,
               uint8_t *output, size_t capacity) {
    if (!pair || !pair->cipher_ready || !input || !output || !length ||
        length > INT_MAX || capacity > INT_MAX) return -1;
    uint64_t &sequence = encrypt ? pair->sent : pair->received;
    if (sequence == std::numeric_limits<uint64_t>::max()) return -1;
    // AOSP writes a little-endian 64-bit sequence into a zero-filled GCM nonce.
    std::array<uint8_t, 12> nonce{};
    for (size_t i = 0; i < sizeof(sequence); ++i) nonce[i] = sequence >> (8 * i);
    size_t written = 0;
    const int accepted = encrypt
        ? EVP_AEAD_CTX_seal(pair->cipher.get(), output, &written, capacity,
                            nonce.data(), nonce.size(), input, length, nullptr, 0)
        : EVP_AEAD_CTX_open(pair->cipher.get(), output, &written, capacity,
                            nonce.data(), nonce.size(), input, length, nullptr, 0);
    if (!accepted || written > INT_MAX) return -1;
    ++sequence;
    return static_cast<int>(written);
}

} // namespace

sc_tls *sc_tls_create(const uint8_t *der, size_t length) {
    ERR_clear_error();
    if (!der || !length) return nullptr;
    CBS source;
    CBS_init(&source, der, length);
    bssl::UniquePtr<RSA> rsa(RSA_parse_private_key(&source));
    bssl::UniquePtr<EVP_PKEY> key(EVP_PKEY_new());
    if (!rsa || CBS_len(&source) || !key || !EVP_PKEY_set1_RSA(key.get(), rsa.get())) return nullptr;
    auto certificate = ClientCertificate(key.get());
    bssl::UniquePtr<SSL_CTX> context(SSL_CTX_new(TLS_method()));
    if (!certificate || !context ||
        !SSL_CTX_set_min_proto_version(context.get(), TLS1_3_VERSION) ||
        !SSL_CTX_set_max_proto_version(context.get(), TLS1_3_VERSION) ||
        !SSL_CTX_use_certificate(context.get(), certificate.get()) ||
        !SSL_CTX_use_PrivateKey(context.get(), key.get())) return nullptr;
    SSL_CTX_set_custom_verify(context.get(), SSL_VERIFY_PEER, AcceptAdbCertificate);
    bssl::UniquePtr<SSL> connection(SSL_new(context.get()));
    bssl::UniquePtr<BIO> inbound(BIO_new(BIO_s_mem()));
    bssl::UniquePtr<BIO> outbound(BIO_new(BIO_s_mem()));
    if (!connection || !inbound || !outbound) return nullptr;
    BIO_set_mem_eof_return(inbound.get(), -1);
    BIO_set_mem_eof_return(outbound.get(), -1);
    SSL_set_bio(connection.get(), inbound.release(), outbound.release());
    SSL_set_connect_state(connection.get());
    auto state = std::unique_ptr<sc_tls>(new (std::nothrow) sc_tls);
    if (!state) return nullptr;
    state->connection = std::move(connection);
    return state.release();
}

void sc_tls_free(sc_tls *tls) { delete tls; }

int sc_tls_handshake(sc_tls *tls) {
    if (!tls) return -1;
    ERR_clear_error();
    const int status = SSL_do_handshake(tls->connection.get());
    if (status == 1) return 1;
    return RecordResult(tls, status) == -2 ? 0 : -1;
}

int sc_tls_feed(sc_tls *tls, const uint8_t *bytes, size_t length) {
    if (!tls || length > INT_MAX || (!bytes && length)) return 0;
    if (!length) return 1;
    return BIO_write(SSL_get_rbio(tls->connection.get()), bytes, static_cast<int>(length)) == static_cast<int>(length);
}

int sc_tls_drain(sc_tls *tls, uint8_t *bytes, size_t capacity) {
    if (!tls || !bytes || !capacity) return 0;
    const int size = BIO_read(SSL_get_wbio(tls->connection.get()), bytes,
                              static_cast<int>(capacity > INT_MAX ? INT_MAX : capacity));
    return size > 0 ? size : 0;
}

int sc_tls_read(sc_tls *tls, uint8_t *bytes, size_t capacity) {
    if (!tls || !bytes || !capacity) return -1;
    ERR_clear_error();
    return RecordResult(tls, SSL_read(tls->connection.get(), bytes,
                         static_cast<int>(capacity > INT_MAX ? INT_MAX : capacity)));
}

int sc_tls_write(sc_tls *tls, const uint8_t *bytes, size_t length) {
    if (!tls || !bytes || !length || length > INT_MAX) return -1;
    ERR_clear_error();
    return RecordResult(tls, SSL_write(tls->connection.get(), bytes, static_cast<int>(length)));
}

int sc_tls_export(sc_tls *tls, uint8_t out[64]) {
    // The terminating NUL is part of AOSP's exporter label.
    static constexpr char label[] = "adb-label";
    return tls && out && SSL_export_keying_material(tls->connection.get(), out, 64,
                           label, sizeof(label), nullptr, 0, 0);
}

void sc_tls_error(char *out, size_t capacity) {
    if (!out || !capacity) return;
    const uint32_t error = ERR_get_error();
    if (error) ERR_error_string_n(error, out, capacity);
    else std::snprintf(out, capacity, "%s", "TLS connection closed or rejected");
}

sc_pair *sc_pair_create(const uint8_t *password, size_t length) {
    if (!password || !length) return nullptr;
    auto state = std::unique_ptr<sc_pair>(new (std::nothrow) sc_pair);
    if (!state) return nullptr;
    // The name terminators are part of AOSP's SPAKE2 identities.
    static constexpr uint8_t client_name[] = "adb pair client";
    static constexpr uint8_t server_name[] = "adb pair server";
    state->exchange.reset(SPAKE2_CTX_new(spake2_role_alice, client_name, sizeof(client_name),
                                         server_name, sizeof(server_name)));
    if (!state->exchange || !SPAKE2_generate_msg(state->exchange.get(), state->public_message.data(),
        &state->public_size, state->public_message.size(), password, length) || !state->public_size) return nullptr;
    return state.release();
}

void sc_pair_free(sc_pair *pair) { delete pair; }

int sc_pair_message(sc_pair *pair, uint8_t *out, size_t capacity) {
    if (!pair || !out || capacity < pair->public_size) return -1;
    std::memcpy(out, pair->public_message.data(), pair->public_size);
    return static_cast<int>(pair->public_size);
}

int sc_pair_process(sc_pair *pair, const uint8_t *message, size_t length) {
    if (!pair || !pair->exchange || !message || !length || length > SPAKE2_MAX_MSG_SIZE) return 0;
    std::array<uint8_t, SPAKE2_MAX_KEY_SIZE> material{};
    size_t material_size = 0;
    const int accepted = SPAKE2_process_msg(pair->exchange.get(), material.data(), &material_size,
                                           material.size(), message, length);
    pair->exchange.reset(); // A PAKE exchange is single-use, including on failure.
    if (!accepted || !material_size) {
        OPENSSL_cleanse(material.data(), material.size());
        return 0;
    }
    std::array<uint8_t, 16> aes_key{};
    static constexpr uint8_t info[] = "adb pairing_auth aes-128-gcm key";
    const int derived = HKDF(aes_key.data(), aes_key.size(), EVP_sha256(), material.data(),
                             material_size, nullptr, 0, info, sizeof(info) - 1);
    OPENSSL_cleanse(material.data(), material.size());
    pair->cipher_ready = derived && EVP_AEAD_CTX_init(pair->cipher.get(), EVP_aead_aes_128_gcm(),
        aes_key.data(), aes_key.size(), EVP_AEAD_DEFAULT_TAG_LENGTH, nullptr);
    OPENSSL_cleanse(aes_key.data(), aes_key.size());
    return pair->cipher_ready;
}

int sc_pair_encrypt(sc_pair *pair, const uint8_t *input, size_t length, uint8_t *out, size_t capacity) {
    return PairRecord(pair, true, input, length, out, capacity);
}

int sc_pair_decrypt(sc_pair *pair, const uint8_t *input, size_t length, uint8_t *out, size_t capacity) {
    return PairRecord(pair, false, input, length, out, capacity);
}
