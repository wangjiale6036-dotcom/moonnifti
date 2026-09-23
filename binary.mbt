///|
pub(all) enum Endian {
  Little
  Big
} derive(Eq)

///|
pub extend Endian with Eq::{equal, not_equal}

///|
pub extend Endian with Show::{output, to_string}

///|
pub impl Show for Endian with fn output(self, logger) {
  logger.write_string(if self == Little { "little" } else { "big" })
}

///|
priv struct Reader {
  bytes : Bytes
  endian : Endian
}

///|
/// All binary reads check bounds before accessing bytes.
fn Reader::bits(
  self : Reader,
  offset : Int,
  width : Int,
) -> UInt64 raise NiftiError {
  require(
    offset >= 0 &&
    width >= 1 &&
    width <= 8 &&
    offset <= self.bytes.length() - width,
    "truncated",
    offset~,
  )
  let mut result = 0UL
  for j in 0..<width {
    let shift = if self.endian == Little { j * 8 } else { (width - j - 1) * 8 }
    result = result | (self.bytes[offset + j].to_uint64() << shift)
  }
  result
}

///|
fn Reader::i16(self : Reader, offset : Int) -> Int raise NiftiError {
  let n = self.bits(offset, 2).to_int()
  if n >= 32768 {
    n - 65536
  } else {
    n
  }
}

///|
fn Reader::i32(self : Reader, offset : Int) -> Int raise NiftiError {
  self.bits(offset, 4).to_uint().reinterpret_as_int()
}

///|
fn Reader::f32(self : Reader, offset : Int) -> Double raise NiftiError {
  Float::reinterpret_from_uint(self.bits(offset, 4).to_uint()).to_double()
}

///|
fn Reader::f64(self : Reader, offset : Int) -> Double raise NiftiError {
  self.bits(offset, 8).reinterpret_as_double()
}

///|
fn put_bits(
  out : FixedArray[Byte],
  endian : Endian,
  offset : Int,
  width : Int,
  value : UInt64,
) -> Unit {
  for j in 0..<width {
    let shift = if endian == Little { j * 8 } else { (width - j - 1) * 8 }
    out[offset + j] = ((value >> shift) & 255UL).to_byte()
  }
}

///|
fn put_i16(
  out : FixedArray[Byte],
  e : Endian,
  offset : Int,
  value : Int,
) -> Unit {
  put_bits(out, e, offset, 2, value.to_uint64())
}

///|
fn put_f32(
  out : FixedArray[Byte],
  e : Endian,
  offset : Int,
  value : Double,
) -> Unit raise NiftiError {
  let f = Float::from_double(value)
  require(finite(value) && !f.is_inf(), "header_float_overflow", offset~)
  put_bits(out, e, offset, 4, f.reinterpret_as_uint().to_uint64())
}

///|
fn copy_bytes(bytes : Bytes, start : Int, count : Int) -> Bytes {
  Bytes::makei(count, i => bytes[start + i])
}

///|
fn checked_product(a : Int, b : Int, limit : Int) -> Int raise NiftiError {
  require(a > 0 && b > 0 && a <= limit / b, "size_limit")
  a * b
}
