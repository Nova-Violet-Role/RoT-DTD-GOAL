use crate::error::EngineError;

pub const MIN: u32 = 1;
pub const MAX: u32 = 3999;

pub(crate) fn value(c: char) -> Option<u32> {
    match c {
        'I' => Some(1),
        'V' => Some(5),
        'X' => Some(10),
        'L' => Some(50),
        'C' => Some(100),
        'D' => Some(500),
        'M' => Some(1000),
        _ => None,
    }
}

pub(crate) fn is_roman_char(c: char) -> bool {
    value(c).is_some()
}

const TABLE: &[(u32, &str)] = &[
    (1000, "M"),
    (900, "CM"),
    (500, "D"),
    (400, "CD"),
    (100, "C"),
    (90, "XC"),
    (50, "L"),
    (40, "XL"),
    (10, "X"),
    (9, "IX"),
    (5, "V"),
    (4, "IV"),
    (1, "I"),
];

pub fn format(n: u32) -> Result<String, EngineError> {
    if n < MIN || n > MAX {
        return Err(EngineError::OutOfRange(format!(
            "{n} is not representable in roman numerals (1..=3999)"
        )));
    }
    let mut n = n;
    let mut out = String::new();
    for &(val, sym) in TABLE {
        while n >= val {
            out.push_str(sym);
            n -= val;
        }
    }
    Ok(out)
}

fn lenient_value(s: &str) -> Result<u32, EngineError> {
    if s.is_empty() {
        return Err(EngineError::InvalidToken(s.to_string()));
    }
    let mut total: i64 = 0;
    let mut prev = 0u32;
    for c in s.chars().rev() {
        let v = value(c).ok_or_else(|| EngineError::InvalidToken(s.to_string()))?;
        if v < prev {
            total -= v as i64;
        } else {
            total += v as i64;
            prev = v;
        }
    }
    if total < MIN as i64 || total > MAX as i64 {
        return Err(EngineError::OutOfRange(format!(
            "{s} is out of the roman numeral range (1..=3999)"
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
mod roman_tests {
    use super::*;

    #[test]
    fn roman_format_basic() {
        assert_eq!(format(1).unwrap(), "I");
        assert_eq!(format(4).unwrap(), "IV");
        assert_eq!(format(9).unwrap(), "IX");
        assert_eq!(format(14).unwrap(), "XIV");
        assert_eq!(format(20).unwrap(), "XX");
        assert_eq!(format(40).unwrap(), "XL");
        assert_eq!(format(90).unwrap(), "XC");
        assert_eq!(format(400).unwrap(), "CD");
        assert_eq!(format(900).unwrap(), "CM");
        assert_eq!(format(3999).unwrap(), "MMMCMXCIX");
    }

    #[test]
    fn roman_format_mcmxciv_boundary() {
        assert_eq!(format(1994).unwrap(), "MCMXCIV");
    }

    #[test]
    fn roman_parse_round_trip() {
        for &(n, s) in &[
            (1u32, "I"),
            (4, "IV"),
            (9, "IX"),
            (14, "XIV"),
            (1994, "MCMXCIV"),
            (3999, "MMMCMXCIX"),
        ] {
            assert_eq!(parse(s).unwrap(), n);
            assert_eq!(format(n).unwrap(), s);
        }
    }

    #[test]
    fn roman_parse_rejects_non_canonical() {
        // IIII is a lenient reading of 4, but canonical form is IV.
        let err = parse("XIIII").unwrap_err();
        match err {
            EngineError::NonCanonical(t) => assert_eq!(t, "XIIII"),
            other => panic!("expected NonCanonical, got {other:?}"),
        }
    }

    #[test]
    fn roman_parse_rejects_invalid_subtractive_pairs_and_repeats() {
        for bad in [
            "IC", "IL", "IM", "VX", "VL", "VM", "LC", "LD", "LM", "DM", "IIII", "VV", "LL", "DD",
            "IIX", "VIV",
        ] {
            assert!(
                matches!(parse(bad), Err(EngineError::NonCanonical(_))),
                "expected {bad} to be rejected as non-canonical"
            );
        }
    }

    #[test]
    fn roman_parse_rejects_invalid_char() {
        assert!(matches!(parse("XIZ"), Err(EngineError::InvalidToken(_))));
    }

    #[test]
    fn roman_parse_rejects_out_of_range() {
        assert!(format(0).is_err());
        assert!(format(4000).is_err());
    }

    #[test]
    fn roman_parse_rejects_empty() {
        assert!(parse("").is_err());
    }
}
