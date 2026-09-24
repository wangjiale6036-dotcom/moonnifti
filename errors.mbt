///|
pub(all) suberror NiftiError {
  NiftiError(String, Int)
} derive(Eq)

///|
pub extend NiftiError with Eq::{equal, not_equal}

///|
pub extend NiftiError with Show::{output, to_string}

///|
pub impl Show for NiftiError with fn output(self, logger) {
  let NiftiError(code, offset) = self
  logger.write_string(code + "@" + offset.to_string())
}

///|
pub fn version() -> String {
  "0.2.0"
}

///|
fn finite(value : Double) -> Bool {
  !value.is_nan() && !value.is_inf()
}

///|
fn require(
  condition : Bool,
  code : String,
  offset? : Int = -1,
) -> Unit raise NiftiError {
  if !condition {
    raise NiftiError(code, offset)
  }
}
