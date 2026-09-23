///|
pub(all) enum Space {
  QForm
  SForm
  PreferSForm
} derive(Eq)

///|
pub extend Space with Eq::{equal, not_equal}

///|
/// Storage is private. Images own their input bytes; methods return copies.
pub struct Image {
  priv header : Bytes
  priv payload : Bytes
  priv shape : FixedArray[Int]
  priv ndim : Int
  priv dtype : Int
  priv width : Int
  priv endian : Endian
  priv slope : Double
  priv intercept : Double
  priv spacing : FixedArray[Double]
  priv qform : Affine?
  priv sform : Affine?
  priv qcode : Int
  priv scode : Int
  priv spatial_unit : Int
  priv time_unit : Int
  priv extension_count : Int
  priv intent : Int
}

///|
pub fn Image::dimensions(self : Image) -> Array[Int] {
  Array::makei(self.ndim, i => self.shape[i])
}

///|
pub fn Image::datatype(self : Image) -> Int {
  self.dtype
}

///|
pub fn Image::byte_order(self : Image) -> Endian {
  self.endian
}

///|
pub fn Image::voxel_count(self : Image) -> Int {
  self.payload.length() / self.width
}

///|
pub fn Image::scaling(self : Image) -> (Double, Double) {
  (self.slope, self.intercept)
}

///|
pub fn Image::voxel_spacing(self : Image) -> Array[Double] {
  Array::makei(self.ndim, i => self.spacing[i])
}

///|
pub fn Image::units(self : Image) -> (Int, Int) {
  (self.spatial_unit, self.time_unit)
}

///|
pub fn Image::form_codes(self : Image) -> (Int, Int) {
  (self.qcode, self.scode)
}

///|
pub fn Image::extensions(self : Image) -> Int {
  self.extension_count
}

///|
/// Unknown space is explicit; there is no invented fallback affine.
pub fn Image::affine(self : Image, space : Space) -> Affine? {
  match space {
    QForm => self.qform
    SForm => self.sform
    PreferSForm =>
      match self.sform {
        Some(_) => self.sform
        None => self.qform
      }
  }
}

///|
pub fn Image::world(
  self : Image,
  x : Double,
  y : Double,
  z : Double,
  space? : Space = PreferSForm,
) -> Array[Double] raise NiftiError {
  match self.affine(space) {
    Some(a) => a.transform(x, y, z)
    None => raise NiftiError("unknown_space", -1)
  }
}

///|
/// Stored samples are decoded without scl_slope/scl_inter.
pub fn Image::raw_at(self : Image, index : Int) -> Double raise NiftiError {
  require(index >= 0 && index < self.voxel_count(), "voxel_index")
  let r : Reader = { bytes: self.payload, endian: self.endian, }
  let p = index * self.width
  match self.dtype {
    2 => r.bytes[p].to_double()
    256 => {
      let v = r.bytes[p].to_int()
      (if v >= 128 { v - 256 } else { v }).to_double()
    }
    4 => r.i16(p).to_double()
    512 => r.bits(p, 2).to_double()
    8 => r.i32(p).to_double()
    768 => r.bits(p, 4).to_double()
    16 => r.f32(p)
    64 => r.f64(p)
    _ => raise NiftiError("unsupported_datatype", 70)
  }
}

///|
pub fn Image::scaled_at(self : Image, index : Int) -> Double raise NiftiError {
  self.raw_at(index) * self.slope + self.intercept
}

///|
pub fn Image::linear_index(
  self : Image,
  x : Int,
  y : Int,
  z : Int,
  t? : Int = 0,
) -> Int raise NiftiError {
  let indices = [x, y, z, t]
  for a in 0..<4 {
    require(indices[a] >= 0 && indices[a] < self.shape[a], "voxel_index")
  }
  x + self.shape[0] * (y + self.shape[1] * (z + self.shape[2] * t))
}

///|
pub fn Image::voxel(
  self : Image,
  x : Int,
  y : Int,
  z : Int,
  t? : Int = 0,
  scaled? : Bool = true,
) -> Double raise NiftiError {
  let i = self.linear_index(x, y, z, t~)
  if scaled {
    self.scaled_at(i)
  } else {
    self.raw_at(i)
  }
}

///|
/// Lossless within the declared file region. Trailing input bytes are rejected.
pub fn Image::to_bytes(self : Image) -> Bytes {
  self.header + self.payload
}
