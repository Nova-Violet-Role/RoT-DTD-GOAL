slint::include_modules!();

use trinum_engine::{eval, format, System};

fn main() -> Result<(), slint::PlatformError> {
    let window = MainWindow::new()?;

    let weak = window.as_weak();
    window.on_evaluate(move || {
        let window = weak.unwrap();
        let expr = window.get_expression();
        match eval(&expr) {
            Ok(n) => {
                let roman = format(n, System::Roman).unwrap_or_default();
                let greek = format(n, System::Greek).unwrap_or_default();
                let egyptian = format(n, System::Egyptian).unwrap_or_default();
                window.set_roman_output(roman.into());
                window.set_greek_output(greek.into());
                window.set_egyptian_output(egyptian.into());
                window.set_error_output("".into());
            }
            Err(e) => {
                window.set_roman_output("".into());
                window.set_greek_output("".into());
                window.set_egyptian_output("".into());
                window.set_error_output(e.to_string().into());
            }
        }
    });

    let weak = window.as_weak();
    window.on_key_pressed(move |key| {
        let window = weak.unwrap();
        let mut expr = window.get_expression().to_string();
        if key.as_str() == "CLR" {
            expr.clear();
        } else {
            expr.push_str(&key);
        }
        window.set_expression(expr.into());
    });

    window.run()
}
