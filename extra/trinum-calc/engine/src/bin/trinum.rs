use std::io::Read;
use std::process::exit;
use trinum_engine::{eval, format, System};

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut out_system: Option<&str> = None;
    let mut i = 1;
    while i < args.len() {
        if args[i] == "--out" {
            out_system = args.get(i + 1).map(|s| s.as_str());
            i += 1;
        }
        i += 1;
    }

    let system = match out_system {
        Some("roman") => System::Roman,
        Some("greek") => System::Greek,
        Some("egyptian") => System::Egyptian,
        _ => {
            eprintln!("error: --out <roman|greek|egyptian> is required");
            exit(2);
        }
    };

    let mut input = String::new();
    if std::io::stdin().read_to_string(&mut input).is_err() {
        eprintln!("error: failed to read stdin");
        exit(2);
    }
    let expr = input.trim();

    match eval(expr).and_then(|n| format(n, system)) {
        Ok(s) => println!("{s}"),
        Err(e) => {
            eprintln!("error: {e}");
            exit(1);
        }
    }
}
