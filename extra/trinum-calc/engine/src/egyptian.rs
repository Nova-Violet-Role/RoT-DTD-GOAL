use crate::error::EngineError;

pub const MIN: u32 = 1;
pub const MAX: u32 = 99_999;

const ONE: char = '𓏺';
const TEN: char = '𓎆';
const HUNDRED: char = '𓍢';
const THOUSAND: char = '𓆼';
const TEN_THOUSAND: char = '𓂭';

fn value(c: char) -> Option<u32> {
    match c {
        ONE => Some(1),
        TEN => Some(10),
        HUNDRED => Some(100),
        THOUSAND => Some(1000),
        TEN_THOUSAND => Some(10_000),
        _ => None,
    }
}

pub(crate) fn is_egyptian_char(c: char) -> bool {
    value(c).is_some()
}

pub fn format(n: u32) -> Result<String, EngineError> {
    if n < MIN || n > MAX {
        return Err(EngineError::OutOfRange(format!(
            "{n} is not representable in egyptian numerals (1..=99999)"
        )));
    }
    let d4 = n / 10_000;
    let d3 = (n / 1_000) % 10;
    let d2 = (n / 100) % 10;
    let d1 = (n / 10) % 10;
    let d0 = n % 10;
    let mut out = String::new();
    out.push_str(&TEN_THOUSAND.to_string().repeat(d4 as usize));
    out.push_str(&THOUSAND.to_string().repeat(d3 as usize));
    out.push_str(&HUNDRED.to_string().repeat(d2 as usize));
    out.push_str(&TEN.to_string().repeat(d1 as usize));
    out.push_str(&ONE.to_string().repeat(d0 as usize));
    Ok(out)
}

fn lenient_value(s: &str) -> Result<u32, EngineError> {
    if s.is_empty() {
        return Err(EngineError::InvalidToken(s.to_string()));
    }
    let mut total: i64 = 0;
    for c in s.chars() {
        let v = value(c).ok_or_else(|| EngineError::InvalidToken(s.to_string()))?;
        total += v as i64;
    }
    if total < MIN as i64 || total > MAX as i64 {
        return Err(EngineError::OutOfRange(format!(
            "{s} is out of the egyptian numeral range (1..=99999)"
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
mod egyptian_tests {
    use super::*;

    #[test]
    fn egyptian_format_basic() {
        assert_eq!(format(1).unwrap(), "𓏺");
        assert_eq!(format(10).unwrap(), "𓎆");
        assert_eq!(format(100).unwrap(), "𓍢");
        assert_eq!(format(1000).unwrap(), "𓆼");
        assert_eq!(format(10_000).unwrap(), "𓂭");
        assert_eq!(format(23).unwrap(), "𓎆𓎆𓏺𓏺𓏺");
    }

    #[test]
    fn egyptian_format_99999_boundary() {
        let expected = "𓂭".repeat(9) + &"𓆼".repeat(9) + &"𓍢".repeat(9) + &"𓎆".repeat(9) + &"𓏺".repeat(9);
        assert_eq!(format(99_999).unwrap(), expected);
    }

    #[test]
    fn egyptian_parse_round_trip() {
        for &(n, s) in &[
            (1u32, "𓏺"),
            (10, "𓎆"),
            (100, "𓍢"),
            (1000, "𓆼"),
            (10_000, "𓂭"),
            (23, "𓎆𓎆𓏺𓏺𓏺"),
        ] {
            assert_eq!(parse(s).unwrap(), n);
            assert_eq!(format(n).unwrap(), s);
        }
        let s99999 = "𓂭".repeat(9) + &"𓆼".repeat(9) + &"𓍢".repeat(9) + &"𓎆".repeat(9) + &"𓏺".repeat(9);
        assert_eq!(parse(&s99999).unwrap(), 99_999);
    }

    #[test]
    fn egyptian_parse_rejects_non_canonical_order() {
        // smallest-to-largest instead of canonical largest-to-smallest
        let err = parse("𓏺𓎆").unwrap_err();
        match err {
            EngineError::NonCanonical(t) => assert_eq!(t, "𓏺𓎆"),
            other => panic!("expected NonCanonical, got {other:?}"),
        }
    }

    #[test]
    fn egyptian_parse_rejects_too_many_repeats() {
        // ten copies of ONE carries into TEN, so this is non-canonical.
        let ten_ones = ONE.to_string().repeat(10);
        assert!(matches!(
            parse(&ten_ones),
            Err(EngineError::NonCanonical(_))
        ));
    }

    #[test]
    fn egyptian_parse_rejects_ten_repeats_of_any_symbol() {
        for c in [ONE, TEN, HUNDRED, THOUSAND] {
            let s = c.to_string().repeat(10);
            assert!(
                matches!(parse(&s), Err(EngineError::NonCanonical(_))),
                "expected 10x{c} to be rejected as non-canonical"
            );
        }
        // ten copies of TEN_THOUSAND overflows the representable range entirely.
        let ten_myriads = TEN_THOUSAND.to_string().repeat(10);
        assert!(parse(&ten_myriads).is_err());
    }

    #[test]
    fn egyptian_parse_rejects_out_of_order_combinations() {
        for bad in ["𓎆𓍢", "𓍢𓆼", "𓆼𓂭", "𓍢𓏺𓎆", "𓎆𓂭", "𓏺𓆼"] {
            assert!(
                matches!(parse(bad), Err(EngineError::NonCanonical(_))),
                "expected {bad} to be rejected as non-canonical"
            );
        }
    }

    #[test]
    fn egyptian_parse_rejects_invalid_char() {
        assert!(matches!(parse("𓏺Z"), Err(EngineError::InvalidToken(_))));
    }

    #[test]
    fn egyptian_parse_rejects_empty() {
        assert!(parse("").is_err());
    }
}
