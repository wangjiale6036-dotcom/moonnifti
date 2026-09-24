///|
fn number(x : Double) -> Json {
  if x.is_nan() || x.is_inf() {
    Json::null()
  } else {
    x.to_json()
  }
}

///|
fn optional(x : Double?) -> Json {
  match x {
    Some(v) => number(v)
    None => Json::null()
  }
}

///|
fn matrix(a : @nifti.Affine?) -> Json {
  match a {
    Some(a) => a.matrix().map(number).to_json()
    None => Json::null()
  }
}

///|
fn describe(img : @nifti.Image) -> Json raise {
  let (slope, intercept) = img.scaling()
  let (spatial, temporal) = img.units()
  let (qcode, scode) = img.form_codes()
  let stats = img.statistics()
  {
    "version": @nifti.version().to_json(),
    "shape": img.dimensions().to_json(),
    "datatype": img.datatype().to_json(),
    "endian": img.byte_order().to_string().to_json(),
    "spacing": img.voxel_spacing().to_json(),
    "voxel_count": img.voxel_count().to_json(),
    "scaling": [slope, intercept].to_json(),
    "units": [spatial, temporal].to_json(),
    "qform_code": qcode.to_json(),
    "sform_code": scode.to_json(),
    "qform": matrix(img.affine(QForm)),
    "sform": matrix(img.affine(SForm)),
    "extension_count": img.extensions().to_json(),
    "statistics": stats_json(stats),
  }
}

///|
fn usage() -> String {
  "MoonNIfTI 0.2.0 — research data, not clinical diagnosis\nUsage (Node.js CLI):\n  inspect INPUT\n  dump INPUT                        # at most 100000 samples\n  slice INPUT AXIS INDEX [T]         # data axis 0/1/2, at most 1M values\n  world INPUT X Y Z [qform|sform|prefer]\n  grid LEFT RIGHT [TOLERANCE_MM]     # exit 2 when incompatible\n  crop INPUT OUTPUT X Y Z NX NY NZ [--drop-extensions]\n  reorient INPUT OUTPUT A0 A1 A2 F0 F1 F2 [--drop-extensions]\n  roi INPUT MASK SELECTION          # SELECTION: nonzero or nonnegative label\n  hist INPUT MASK SELECTION FRAME LOWER UPPER BINS\n  roi-crop INPUT MASK OUTPUT SELECTION [MARGIN] [--drop-extensions]\nROI commands require matching static mask grids; prefer sform, then qform.\nroi-crop exports a rectangular box, not a masked volume. Margin is voxels.\nAxes are new-to-old indices, flips are 0/1. Outputs must not exist.\n.nii.gz input is bounded; .gz output uses gzip. No interpolation."
}

///|
fn demand(condition : Bool) -> Unit raise @nifti.NiftiError {
  if !condition {
    raise @nifti.NiftiError("invalid_arguments", -1)
  }
}

///|
fn load(path : String) -> @nifti.Image raise @nifti.NiftiError {
  let b = read_file(path)
  if b.length() == 0 {
    raise @nifti.NiftiError("input_read_or_gzip_failed", -1)
  }
  @nifti.read(b)
}

///|
fn integer(value : String) -> Int raise {
  let n = @string.parse_int(value)
  demand(n.to_string() == value)
  n
}

///|
fn run() -> Unit raise {
  let all = @env.args()
  let args = all[2:].to_owned()
  if args.is_empty() || args[0] == "--help" || args[0] == "help" {
    println(usage())
    return
  }
  if args[0] == "--version" {
    demand(args.length() == 1)
    println(@nifti.version())
    return
  }
  let command = args[0]
  demand(
    [
      "inspect", "dump", "slice", "world", "grid", "crop", "reorient", "roi", "roi-crop",
      "hist",
    ].contains(command),
  )
  demand(args.length() >= 2)
  let img = load(args[1])
  match command {
    "roi" | "roi-crop" | "hist" => run_roi(args, img)
    "inspect" => {
      demand(args.length() == 2)
      println(describe(img).stringify(indent=2))
    }
    "dump" => {
      demand(args.length() == 2)
      if img.voxel_count() > 100000 {
        raise @nifti.NiftiError("dump_limit", -1)
      }
      let raw = []
      let scaled = []
      for i in 0..<img.voxel_count() {
        raw.push(number(img.raw_at(i)))
        scaled.push(number(img.scaled_at(i)))
      }
      let output : Json = {
        "image": describe(img),
        "raw": raw.to_json(),
        "scaled": scaled.to_json(),
      }
      println(output.stringify())
    }
    "slice" => {
      demand(args.length() == 4 || args.length() == 5)
      let axis = integer(args[2])
      let index = integer(args[3])
      demand(axis >= 0 && axis < 3)
      let d = img.dimensions()
      let n = d[0] * d[1] * d[2] / d[axis]
      if n > 1000000 {
        raise @nifti.NiftiError("slice_output_limit", -1)
      }
      let t = if args.length() == 5 { integer(args[4]) } else { 0 }
      let s = img.slice(axis, index, t~)
      let out : Json = {
        "axis": axis.to_json(),
        "index": index.to_json(),
        "time": t.to_json(),
        "width": s.width.to_json(),
        "height": s.height.to_json(),
        "values": s.values.map(number).to_json(),
      }
      println(out.stringify())
    }
    "world" => {
      demand(args.length() == 5 || args.length() == 6)
      let space = if args.length() == 5 { "prefer" } else { args[5] }
      let choice = match space {
        "qform" => @nifti.Space::QForm
        "sform" => @nifti.Space::SForm
        "prefer" => @nifti.Space::PreferSForm
        _ => raise @nifti.NiftiError("space_option", -1)
      }
      let point = img.world(
        @string.parse_double(args[2]),
        @string.parse_double(args[3]),
        @string.parse_double(args[4]),
        space=choice,
      )
      let out : Json = {
        "space": space.to_json(),
        "spatial_unit_code": img.units().0.to_json(),
        "world": point.to_json(),
      }
      println(out.stringify())
    }
    "grid" => {
      demand(args.length() == 3 || args.length() == 4)
      let tol = if args.length() == 4 {
        @string.parse_double(args[3])
      } else {
        0.001
      }
      let result = img.compare_grid(load(args[2]), tolerance_mm=tol)
      let out : Json = {
        "compatible": result.compatible.to_json(),
        "reason": result.reason.to_json(),
        "maximum_corner_error_mm": optional(result.maximum_corner_error_mm),
        "tolerance_mm": tol.to_json(),
      }
      println(out.stringify())
      if !result.compatible {
        exit_code(2)
      }
    }
    "crop" | "reorient" => {
      demand(
        args.length() == 9 ||
        (args.length() == 10 && args[9] == "--drop-extensions"),
      )
      let first = [integer(args[3]), integer(args[4]), integer(args[5])]
      let second = [integer(args[6]), integer(args[7]), integer(args[8])]
      let drop_extensions = args.length() == 10
      let result = if command == "crop" {
        img.crop(first, second, drop_extensions~)
      } else {
        demand(second.iter().all(x => x == 0 || x == 1))
        img.reorient(first, second.map(x => x == 1), drop_extensions~)
      }
      // Complete validation and report generation before publishing the output.
      let report : Json = {
        "operation": command.to_json(),
        "warnings": result.warnings.to_json(),
        "image": describe(result.image),
      }
      if !write_file(args[2], result.image.to_bytes()) {
        raise @nifti.NiftiError("output_write_failed_or_exists", -1)
      }
      println(report.stringify(indent=2))
    }
    _ => raise @nifti.NiftiError("invalid_arguments", -1)
  }
}

///|
fn main {
  run() catch {
    @nifti.NiftiError(code, offset) =>
      report_error("moonnifti: " + code + "@" + offset.to_string())
    _ => report_error("moonnifti: invalid_arguments_or_internal_error")
  }
}
