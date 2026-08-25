import std.process.*
import std.env.*

main(): Int64 {
    let args = getCommandLine()
    if (args.size >= 2 && args[1] == "pre-build") {
        match (getVariable("MARKDOWN_NATIVE_SCANNER")) {
            case Some("1") => execute("python3", "scripts/build_native_scanner.py", "--enable", "--out-dir",
                "target/native")
            case Some("true") => execute("python3", "scripts/build_native_scanner.py", "--enable", "--out-dir",
                "target/native")
            case _ => 0
        }
    } else {
        0
    }
}
