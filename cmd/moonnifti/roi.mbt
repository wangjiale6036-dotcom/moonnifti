///|
fn selection(value : String) -> @nifti.MaskSelection raise {
  if value == "nonzero" {
    @nifti.MaskSelection::NonZero
  } else {
    @nifti.MaskSelection::Label(integer(value))
  }
}

///|
fn stats_json(stats : @nifti.Statistics) -> Json {
  {
    "finite_count": stats.finite_count.to_json(),
    "nan_count": stats.nan_count.to_json(),
    "positive_infinity_count": stats.positive_infinity_count.to_json(),
    "negative_infinity_count": stats.negative_infinity_count.to_json(),
    "minimum": optional(stats.minimum),
    "maximum": optional(stats.maximum),
    "mean": optional(stats.mean),
  }
}

///|
fn region_json(region : @nifti.Region) -> Json raise {
  let bounds : Json = match region.bounds() {
    None => Json::null()
    Some(b) =>
      {
        "start": [b.x, b.y, b.z].to_json(),
        "size": [b.nx, b.ny, b.nz].to_json(),
      }
  }
  let frames = region
    .time_series()
    .map(frame => {
      "frame": frame.frame.to_json(),
      "time_seconds": optional(frame.time_seconds),
      "statistics": stats_json(frame.statistics),
    })
  {
    "selected_voxels": region.count().to_json(),
    "bounds": bounds,
    "space_policy": "prefer-sform".to_json(),
    "centroid_mm": region
    .centroid_mm()
    .map(x => x.to_json())
    .unwrap_or(Json::null()),
    "volume_mm3": number(region.volume_mm3()),
    "frames": frames.to_json(),
  }
}

///|
fn run_roi(args : Array[String], image : @nifti.Image) -> Unit raise {
  match args[0] {
    "roi" => {
      demand(args.length() == 4)
      let region = image.select_region(load(args[2]), selection(args[3]))
      println(region_json(region).stringify(indent=2))
    }
    "hist" => {
      demand(args.length() == 8)
      let region = image.select_region(load(args[2]), selection(args[3]))
      let h = region.histogram(
        integer(args[4]),
        @string.parse_double(args[5]),
        @string.parse_double(args[6]),
        integer(args[7]),
      )
      let report : Json = {
        "selected_voxels": region.count().to_json(),
        "lower": number(h.lower),
        "upper": number(h.upper),
        "counts": h.counts.to_json(),
        "below_range": h.below_range.to_json(),
        "above_range": h.above_range.to_json(),
        "nan_count": h.nan_count.to_json(),
        "positive_infinity_count": h.positive_infinity_count.to_json(),
        "negative_infinity_count": h.negative_infinity_count.to_json(),
      }
      println(report.stringify(indent=2))
    }
    "roi-crop" => {
      demand(args.length() >= 5 && args.length() <= 7)
      let drop_extensions = args[args.length() - 1] == "--drop-extensions"
      let count = args.length() - (if drop_extensions { 1 } else { 0 })
      demand(count == 5 || count == 6)
      let margin = if count == 6 { integer(args[5]) } else { 0 }
      let region = image.select_region(load(args[2]), selection(args[4]))
      let transformed = region.crop(margin~, drop_extensions~)
      let report : Json = {
        "operation": "roi-crop".to_json(),
        "rectangle_not_masked": true.to_json(),
        "margin_voxels": margin.to_json(),
        "region": region_json(region),
        "warnings": transformed.warnings.to_json(),
        "image": describe(transformed.image),
      }
      if !write_file(args[3], transformed.image.to_bytes()) {
        raise @nifti.NiftiError("output_write_failed_or_exists", -1)
      }
      println(report.stringify(indent=2))
    }
    _ => raise @nifti.NiftiError("invalid_arguments", -1)
  }
}
