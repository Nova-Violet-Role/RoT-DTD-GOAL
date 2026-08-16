mod egyptian;
mod error;
mod eval;
mod greek;
mod roman;

pub use error::EngineError;
pub use eval::eval;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum System {
    Roman,
    Greek,
    Egyptian,
}

fn detect_system(token: &str) -> Result<System, EngineError> {
    if token.is_empty() {
        return Err(EngineError::UnknownToken(token.to_string()));
    }
    let mut has_roman = false;
    let mut has_greek = false;
    let mut has_egyptian = false;
    for c in token.chars() {
        if roman::is_roman_char(c) {
            has_roman = true;
        } else if greek::is_greek_char(c) {
            has_greek = true;
        } else if egyptian::is_egyptian_char(c) {
            has_egyptian = true;
        } else {
            return Err(EngineError::UnknownToken(token.to_string()));
        }
    }
    match (has_roman, has_greek, has_egyptian) {
        (true, false, false) => Ok(System::Roman),
        (false, true, false) => Ok(System::Greek),
        (false, false, true) => Ok(System::Egyptian),
        _ => Err(EngineError::UnknownToken(token.to_string())),
    }
}

/// Auto-detects the numeral system of `token` and parses it to a value.
pub fn parse(token: &str) -> Result<u32, EngineError> {
    match detect_system(token)? {
        System::Roman => roman::parse(token),
        System::Greek => greek::parse(token),
        System::Egyptian => egyptian::parse(token),
    }
}

/// Formats `n` canonically in the requested numeral `system`.
pub fn format(n: u32, system: System) -> Result<String, EngineError> {
    match system {
        System::Roman => roman::format(n),
        System::Greek => greek::format(n),
        System::Egyptian => egyptian::format(n),
    }
}

#[cfg(test)]
mod detect_tests {
    use super::*;

    #[test]
    fn detect_disambiguates_all_three_systems() {
        assert_eq!(detect_system("XIV").unwrap(), System::Roman);
        assert_eq!(detect_system("\u{0375}α").unwrap(), System::Greek);
        assert_eq!(detect_system("𓎆𓏺").unwrap(), System::Egyptian);
    }

    #[test]
    fn detect_rejects_mixed_system_token() {
        assert!(detect_system("X\u{0375}α").is_err());
    }

    #[test]
    fn parse_auto_detects() {
        assert_eq!(parse("XIV").unwrap(), 14);
        assert_eq!(parse("ρ").unwrap(), 100);
        assert_eq!(parse("𓎆").unwrap(), 10);
    }
}
