use crate::error::EngineError;

#[derive(Debug, Clone, PartialEq)]
enum Token {
    Num(String),
    Plus,
    Minus,
    Star,
    Slash,
    LParen,
    RParen,
}

fn tokenize(expr: &str) -> Vec<Token> {
    let mut tokens = Vec::new();
    let mut buf = String::new();
    let flush = |buf: &mut String, tokens: &mut Vec<Token>| {
        if !buf.is_empty() {
            tokens.push(Token::Num(std::mem::take(buf)));
        }
    };
    for c in expr.chars() {
        match c {
            c if c.is_whitespace() => flush(&mut buf, &mut tokens),
            '+' => {
                flush(&mut buf, &mut tokens);
                tokens.push(Token::Plus);
            }
            '-' => {
                flush(&mut buf, &mut tokens);
                tokens.push(Token::Minus);
            }
            '*' => {
                flush(&mut buf, &mut tokens);
                tokens.push(Token::Star);
            }
            '/' => {
                flush(&mut buf, &mut tokens);
                tokens.push(Token::Slash);
            }
            '(' => {
                flush(&mut buf, &mut tokens);
                tokens.push(Token::LParen);
            }
            ')' => {
                flush(&mut buf, &mut tokens);
                tokens.push(Token::RParen);
            }
            _ => buf.push(c),
        }
    }
    flush(&mut buf, &mut tokens);
    tokens
}

struct Parser<'a> {
    tokens: &'a [Token],
    pos: usize,
    expr: &'a str,
}

impl<'a> Parser<'a> {
    fn peek(&self) -> Option<&Token> {
        self.tokens.get(self.pos)
    }

    fn parse_expr(&mut self) -> Result<i64, EngineError> {
        let mut val = self.parse_term()?;
        loop {
            match self.peek() {
                Some(Token::Plus) => {
                    self.pos += 1;
                    let rhs = self.parse_term()?;
                    val = val
                        .checked_add(rhs)
                        .ok_or_else(|| EngineError::Overflow(self.expr.to_string()))?;
                }
                Some(Token::Minus) => {
                    self.pos += 1;
                    let rhs = self.parse_term()?;
                    val = val
                        .checked_sub(rhs)
                        .ok_or_else(|| EngineError::Underflow(self.expr.to_string()))?;
                }
                _ => break,
            }
        }
        Ok(val)
    }

    fn parse_term(&mut self) -> Result<i64, EngineError> {
        let mut val = self.parse_factor()?;
        loop {
            match self.peek() {
                Some(Token::Star) => {
                    self.pos += 1;
                    let rhs = self.parse_factor()?;
                    val = val
                        .checked_mul(rhs)
                        .ok_or_else(|| EngineError::Overflow(self.expr.to_string()))?;
                }
                Some(Token::Slash) => {
                    self.pos += 1;
                    let rhs = self.parse_factor()?;
                    if rhs == 0 {
                        return Err(EngineError::DivByZero(self.expr.to_string()));
                    }
                    val /= rhs;
                }
                _ => break,
            }
        }
        Ok(val)
    }

    fn parse_factor(&mut self) -> Result<i64, EngineError> {
        match self.peek().cloned() {
            Some(Token::LParen) => {
                self.pos += 1;
                let val = self.parse_expr()?;
                match self.peek() {
                    Some(Token::RParen) => {
                        self.pos += 1;
                        Ok(val)
                    }
                    _ => Err(EngineError::UnbalancedParens),
                }
            }
            Some(Token::Num(s)) => {
                self.pos += 1;
                let v = crate::parse(&s)?;
                Ok(v as i64)
            }
            Some(other) => Err(EngineError::UnexpectedToken(format!("{other:?}"))),
            None => Err(EngineError::EmptyExpression),
        }
    }
}

/// Evaluates a mixed-system arithmetic expression to a single value.
///
/// Numeral tokens may come from any of the three systems, freely mixed.
/// Division truncates. A zero, negative, or overflowing result is an
/// error since none of the three numeral systems can represent zero.
pub fn eval(expr: &str) -> Result<u32, EngineError> {
    let tokens = tokenize(expr);
    if tokens.is_empty() {
        return Err(EngineError::EmptyExpression);
    }
    let mut parser = Parser {
        tokens: &tokens,
        pos: 0,
        expr,
    };
    let val = parser.parse_expr()?;
    if parser.pos != tokens.len() {
        return Err(EngineError::UnexpectedToken(expr.to_string()));
    }
    if val <= 0 {
        return Err(EngineError::ZeroResult(expr.to_string()));
    }
    if val > u32::MAX as i64 {
        return Err(EngineError::Overflow(expr.to_string()));
    }
    Ok(val as u32)
}

#[cfg(test)]
mod eval_tests {
    use super::*;

    #[test]
    fn eval_basic_addition_roman() {
        assert_eq!(eval("XIV + VI").unwrap(), 20);
    }

    #[test]
    fn eval_multiplication_greek_input() {
        assert_eq!(eval("X * X").unwrap(), 100);
    }

    #[test]
    fn eval_mixed_systems_freely() {
        // XIV(14) + ͵α(1000) - 𓎆𓏺(11) = 1003
        assert_eq!(eval("XIV + \u{0375}α - 𓎆𓏺").unwrap(), 1003);
    }

    #[test]
    fn eval_operator_precedence() {
        // II(2) + III(3) * IV(4) = 2 + 12 = 14
        assert_eq!(eval("II + III * IV").unwrap(), 14);
    }

    #[test]
    fn eval_parentheses() {
        // (II + III) * IV = 5 * 4 = 20
        assert_eq!(eval("(II + III) * IV").unwrap(), 20);
    }

    #[test]
    fn eval_division_truncates() {
        // X / III = 10 / 3 = 3
        assert_eq!(eval("X / III").unwrap(), 3);
    }

    #[test]
    fn eval_division_by_zero_is_err() {
        // a zero divisor can't be spelled directly (no zero numeral), but
        // a subtraction can produce one at evaluation time.
        assert!(matches!(
            eval("X / (II - II)"),
            Err(EngineError::DivByZero(_))
        ));
    }

    #[test]
    fn eval_zero_result_is_err() {
        assert!(matches!(eval("V - V"), Err(EngineError::ZeroResult(_))));
    }

    #[test]
    fn eval_negative_result_is_err() {
        assert!(matches!(eval("I - V"), Err(EngineError::ZeroResult(_))));
    }

    #[test]
    fn eval_unbalanced_parens_is_err() {
        assert!(matches!(
            eval("(II + III"),
            Err(EngineError::UnbalancedParens)
        ));
    }

    #[test]
    fn eval_empty_expression_is_err() {
        assert!(matches!(eval(""), Err(EngineError::EmptyExpression)));
        assert!(matches!(eval("   "), Err(EngineError::EmptyExpression)));
    }

    #[test]
    fn eval_invalid_token_named_in_error() {
        let err = eval("XIIII + I").unwrap_err();
        match err {
            EngineError::NonCanonical(t) => assert_eq!(t, "XIIII"),
            other => panic!("expected NonCanonical, got {other:?}"),
        }
    }
}
