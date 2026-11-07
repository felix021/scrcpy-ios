import Foundation

final class RemoteSettings {
    private let stream: AdbStream
    private let writer = DispatchQueue(label: "scrcpy.settings")
    private let ready = DispatchSemaphore(value: 0), exited = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var stopping = false
    init(connection: AdbConnection, serverPath: String, micPath: String, warning: @escaping (String) -> Void, failure: @escaping (Error) -> Void) throws {
        let command = """
        a=$(settings get system accelerometer_rotation </dev/null); r=$(settings get system user_rotation </dev/null); v=$(settings get global stay_on_while_plugged_in </dev/null);
        s=$(wm size </dev/null | tail -n 1); s=${s##*: }; w=${s%x*}; h=${s#*x}; sdk=$(getprop ro.build.version.sdk </dev/null); rd=0; wd=0; manual=;
        restore_rotation(){ manual=; if [ "$rd" = 1 ]; then if [ "$r" = null ]; then settings delete system user_rotation </dev/null; else settings put system user_rotation "$r" </dev/null; fi; if [ "$a" = null ]; then settings delete system accelerometer_rotation </dev/null; else settings put system accelerometer_rotation "$a" </dev/null; fi; rd=0; fi; };
        restore_awake(){ if [ "$wd" = 1 ]; then if [ "$v" = null ]; then settings delete global stay_on_while_plugged_in </dev/null; else settings put global stay_on_while_plugged_in "$v" </dev/null; fi; wd=0; fi; };
        apply_rotation(){ rd=1; if [ "$sdk" -ge 29 ]; then wm user-rotation lock "$1" </dev/null; else settings put system accelerometer_rotation 0 </dev/null; settings put system user_rotation "$1" </dev/null; fi; };
        trap 'restore_rotation; restore_awake; rm -f \(serverPath) \(micPath)' EXIT; trap 'exit' HUP INT TERM; echo READY;
        while IFS= read -r d; do case "$d" in q) break;; r) restore_rotation;; w0) restore_awake;; w1) wd=1; settings put global stay_on_while_plugged_in 7 </dev/null;;
        0|1) manual=; if [ "$w" -gt "$h" ]; then d=$((1-d)); fi; apply_rotation "$d";;
        L|R) rd=1; if [ -n "$manual" ]; then c=$manual; elif [ "$sdk" -ge 29 ]; then wm user-rotation lock </dev/null; c=$(trap - EXIT HUP INT TERM; settings get system user_rotation </dev/null); else c=$(trap - EXIT HUP INT TERM; dumpsys input </dev/null | sed -n 's/.*SurfaceOrientation: *\\([0-3]\\).*/\\1/p' | head -n 1); fi;
        case "$c" in 0|1|2|3) if [ "$d" = L ]; then c=$(((c+3)%4)); else c=$(((c+1)%4)); fi; apply_rotation "$c"; manual=$c;; *) restore_rotation; echo ROTATION_FAILED;; esac;; esac; echo APPLIED:$d; done
        """
        stream = try connection.open("shell:" + command)
        Thread.detachNewThread { [self] in
            var pending = Data()
            do {
                while true {
                    pending += try stream.readChunk()
                    while let index = pending.firstIndex(of: 10) {
                        let line = String(decoding: pending.prefix(upTo: index), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                        pending.removeSubrange(...index)
                        if line == "READY" { ready.signal() }
                        if line == "ROTATION_FAILED" { warning("Remote rotation is unavailable") }
                    }
                }
            } catch { if !lock.withValue({ stopping }) { failure(error) } }
            exited.signal()
        }
        guard ready.wait(timeout: .now() + 10) == .success else { stream.close(); throw ScrcpyError.message("Remote settings service did not start") }
    }
    func send(_ value: String) { writer.async { [self] in guard !lock.withValue({ stopping }) else { return }; try? stream.write(Data((value + "\n").utf8)) } }
    func finish() {
        lock.withValue { stopping = true }
        let done = DispatchSemaphore(value: 0)
        writer.async { [self] in try? stream.write(Data("q\n".utf8)); try? stream.flush(timeout: 1); done.signal() }
        _ = done.wait(timeout: .now() + 2); _ = exited.wait(timeout: .now() + 2); stream.close()
    }
    func cancel() { lock.withValue { stopping = true }; stream.close() }
}
