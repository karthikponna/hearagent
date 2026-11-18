use hearagent_core::servers::{detect_framework, is_dev_server, parse_etime, parse_lsof_cwd, parse_lsof_listen, parse_ps};

#[test]
fn parses_lsof_listen_and_dedupes_ipv4_ipv6() {
    let out = "p4242\ncnode\nn*:3000\nn[::1]:3000\np5151\ncPython\nn127.0.0.1:8000\np77\ncrapportd\nn*:49152\n";
    assert_eq!(
        parse_lsof_listen(out),
        vec![(77, "rapportd".to_string(), 49152), (4242, "node".to_string(), 3000), (5151, "Python".to_string(), 8000)]
    );
}

#[test]
fn parses_cwd_and_ps() {
    let cwd = parse_lsof_cwd("p4242\nfcwd\nn/Users/dev/code/storefront\np5151\nfcwd\nn/Users/dev/code/search\n");
    assert_eq!(cwd[&4242], "/Users/dev/code/storefront");
    let ps = parse_ps(" 4242   02:14:05 node /Users/dev/code/storefront/node_modules/.bin/next dev\n5151 1-00:00:03 python -m uvicorn main:app\n");
    assert_eq!(ps[&4242], (2 * 3600 + 14 * 60 + 5, "node /Users/dev/code/storefront/node_modules/.bin/next dev".into()));
    assert_eq!(ps[&5151].0, 86_403);
}

#[test]
fn etime_formats() {
    assert_eq!(parse_etime("00:05"), Some(5));
    assert_eq!(parse_etime("1:02:03"), Some(3723));
    assert_eq!(parse_etime("2-00:00:00"), Some(172_800));
    assert_eq!(parse_etime("bad"), None);
}

#[test]
fn filters_and_names_dev_servers() {
    assert!(is_dev_server("node", "/Users/dev/code/storefront", "node next dev", 3000));
    assert!(is_dev_server("python3.12", "/", "python3 -m http.server", 8000));
    assert!(!is_dev_server("node", "/Users/dev/code/app", "node x", 80), "privileged ports are not dev servers");
    assert!(!is_dev_server("Cursor Helper", "/Users/dev", "/Applications/Cursor.app/Contents/x", 51000));
    assert!(!is_dev_server("rapportd", "/", "/usr/libexec/rapportd", 49152));

    assert_eq!(detect_framework("node", "node /x/node_modules/.bin/next dev", 3000), "Next.js");
    assert_eq!(detect_framework("node", "node /x/node_modules/.bin/vite", 5173), "Vite");
    assert_eq!(detect_framework("Python", "python -m uvicorn main:app", 8000), "FastAPI");
    assert_eq!(detect_framework("node", "node cli.js start", 8081), "Metro");
    assert_eq!(detect_framework("bun", "bun run server.ts", 4000), "Bun");
}
