use crate::error::EngineError;

pub const MIN: u32 = 1;
pub const MAX: u32 = 9999;

const THOUSANDS_PREFIX: char = '\u{0375}'; // ͵ GREEK LOWER NUMERAL SIGN

const UNITS: [char; 9] = ['α', 'β', 'γ', 'δ', 'ε', 'ϛ', 'ζ', 'η', 'θ'];
const TENS: [char; 9] = ['ι', 'κ', 'λ', 'μ', 'ν', 'ξ', 'ο', 'π', 'ϟ'];
const HUNDREDS: [char; 9] = ['ρ', 'σ', 'τ', 'υ', 'φ', 'χ', 'ψ', 'ω', 'ϡ'];

fn letter_value(c: char) -> Option<u32> {
    if let Some(i) = UNITS.iter().position(|&u| u == c) {
        return Some(i as u32 + 1);
    }
    if let Some(i) = TENS.iter().position(|&u| u == c) {
        return Some((i as u32 + 1) * 10);
    }
    if let Some(i) = HUNDREDS.iter().position(|&u| u == c) {
        return Some((i as u32 + 1) * 100);
    }
    None
}

pub(crate) fn is_greek_char(c: char) -> bool {
    c == THOUSANDS_PREFIX || letter_value(c).is_some()
}

pub fn format(n: u32) -> Result<String, EngineError> {
    if n < MIN || n > MAX {
        return Err(EngineError::OutOfRange(format!(
            "{n} is not representable in greek numerals (1..=9999)"
        )));
    }
    let th = n / 1000;
    let h = (n / 100) % 10;
    let t = (n / 10) % 10;
    let u = n % 10;
    let mut out = String::new();
    if th > 0 {
        out.push(THOUSANDS_PREFIX);
        out.push(UNITS[(th - 1) as usize]);
    }
    if h > 0 {
        out.push(HUNDREDS[(h - 1) as usize]);
    }
    if t > 0 {
        out.push(TENS[(t - 1) as usize]);
    }
    if u > 0 {
        out.push(UNITS[(u - 1) as usize]);
    }
    Ok(out)
}

fn lenient_value(s: &str) -> Result<u32, EngineError> {
    let chars: Vec<char> = s.chars().collect();
    if chars.is_empty() {
        return Err(EngineError::InvalidToken(s.to_string()));
    }
    let mut idx = 0;
    let mut total: i64 = 0;
    if chars[0] == THOUSANDS_PREFIX {
        let digit_char = chars
            .get(1)
            .ok_or_else(|| EngineError::InvalidToken(s.to_string()))?;
        let v = UNITS
            .iter()
            .position(|&u| u == *digit_char)
            .map(|i| i as u32 + 1)
            .ok_or_else(|| EngineError::InvalidToken(s.to_string()))?;
        total += (v * 1000) as i64;
        idx = 2;
    }
    for &c in &chars[idx..] {
        let v = letter_value(c).ok_or_else(|| EngineError::InvalidToken(s.to_string()))?;
        total += v as i64;
    }
    if total < MIN as i64 || total > MAX as i64 {
        return Err(EngineError::OutOfRange(format!(
            "{s} is out of the greek numeral range (1..=9999)"
        )));
    }
    Ok(total as u32)
}

pub fn parse(s: &str) -> Result<u32, EngineError> {
    let v = lenient_value(s)?;
    let canonical = format(v)?;
    if canonical != s {
        return Err(EngineError::NonCanonical(s.to_string()));
    }
    Ok(v)
}

#[cfg(test)]
mod greek_tests {
    use super::*;

    #[test]
    fn greek_format_basic() {
        assert_eq!(format(1).unwrap(), "α");
        assert_eq!(format(9).unwrap(), "θ");
        assert_eq!(format(10).unwrap(), "ι");
        assert_eq!(format(90).unwrap(), "ϟ");
        assert_eq!(format(100).unwrap(), "ρ");
        assert_eq!(format(900).unwrap(), "ϡ");
        assert_eq!(format(1000).unwrap(), "\u{0375}α");
    }

    #[test]
    fn greek_format_9999_boundary() {
        // ͵θϡϟθ = 9000 + 900 + 90 + 9 = 9999
        assert_eq!(format(9999).unwrap(), "\u{0375}θϡϟθ");
    }

    #[test]
    fn greek_parse_round_trip() {
        for &(n, s) in &[
            (1u32, "α"),
            (100, "ρ"),
            (1000, "\u{0375}α"),
            (9999, "\u{0375}θϡϟθ"),
            (1994, "\u{0375}αϡϟδ"),
        ] {
            assert_eq!(parse(s).unwrap(), n);
            assert_eq!(format(n).unwrap(), s);
        }
    }

    #[test]
    fn greek_parse_rejects_non_canonical() {
        // αβ sums to 3 leniently, but canonical 3 is γ.
        let err = parse("αβ").unwrap_err();
        match err {
            EngineError::NonCanonical(t) => assert_eq!(t, "αβ"),
            other => panic!("expected NonCanonical, got {other:?}"),
        }
    }

    #[test]
    fn greek_parse_rejects_out_of_place_order_and_repeats() {
        for bad in ["ιρ", "αα", "ιι", "ρρ", "ραι"] {
            assert!(
                matches!(parse(bad), Err(EngineError::NonCanonical(_))),
                "expected {bad} to be rejected as non-canonical"
            );
        }
    }

    #[test]
    fn greek_parse_rejects_thousands_prefix_without_units_letter() {
        // prefix followed by a tens-place letter instead of a units-place one
        assert!(matches!(
            parse("\u{0375}ι"),
            Err(EngineError::InvalidToken(_))
        ));
        // prefix with nothing following it
        assert!(matches!(
            parse("\u{0375}"),
            Err(EngineError::InvalidToken(_))
        ));
    }

    #[test]
    fn greek_parse_rejects_invalid_char() {
        assert!(matches!(parse("αZ"), Err(EngineError::InvalidToken(_))));
    }

    #[test]
    fn greek_parse_rejects_out_of_range() {
        assert!(format(0).is_err());
        assert!(format(10000).is_err());
    }

    #[test]
    fn greek_parse_rejects_empty() {
        assert!(parse("").is_err());
    }

    #[test]
    fn greek_keraia_not_emitted() {
        assert!(!format(1).unwrap().contains('\u{02B9}'));
    }
}
