use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EngineError {
    InvalidToken(String),
    NonCanonical(String),
    OutOfRange(String),
    UnknownToken(String),
    DivByZero(String),
    Overflow(String),
    Underflow(String),
    ZeroResult(String),
    UnbalancedParens,
    EmptyExpression,
    UnexpectedToken(String),
}

impl fmt::Display for EngineError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            EngineError::InvalidToken(t) => write!(f, "invalid numeral token: {t}"),
            EngineError::NonCanonical(t) => write!(f, "non-canonical numeral: {t}"),
            EngineError::OutOfRange(t) => write!(f, "numeral out of range: {t}"),
            EngineError::UnknownToken(t) => write!(f, "unrecognized token: {t}"),
            EngineError::DivByZero(t) => write!(f, "division by zero in: {t}"),
            EngineError::Overflow(t) => write!(f, "overflow computing: {t}"),
            EngineError::Underflow(t) => write!(f, "underflow computing: {t}"),
            EngineError::ZeroResult(t) => write!(f, "result is zero (unrepresentable) in: {t}"),
            EngineError::UnbalancedParens => write!(f, "unbalanced parentheses"),
            EngineError::EmptyExpression => write!(f, "empty expression"),
            EngineError::UnexpectedToken(t) => write!(f, "unexpected token: {t}"),
        }
    }
}

impl std::error::Error for EngineError {}
