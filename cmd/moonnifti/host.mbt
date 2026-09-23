///|
/// Host-only file/container operations. All NIfTI semantics are in the core.
extern "js" fn read_file(name : String) -> Bytes =
  #|(name) => {
  #|  const fs = require('node:fs'), zlib = require('node:zlib');
  #|  let fd;
  #|  try {
  #|    fd = fs.openSync(name, 'r');
  #|    const stat = fs.fstatSync(fd), limit = 268435456;
  #|    if (!stat.isFile() || stat.size < 1 || stat.size > limit) return new Uint8Array(0);
  #|    const data = Buffer.alloc(stat.size);
  #|    let done = 0;
  #|    while (done < data.length) {
  #|      const n = fs.readSync(fd, data, done, data.length - done, null);
  #|      if (!n) return new Uint8Array(0);
  #|      done += n;
  #|    }
  #|    if (fs.readSync(fd, Buffer.alloc(1), 0, 1, null)) return new Uint8Array(0);
  #|    return data[0] === 31 && data[1] === 139
  #|      ? zlib.gunzipSync(data, {maxOutputLength: limit}) : data;
  #|  } catch (_) { return new Uint8Array(0); }
  #|  finally { if (fd !== undefined) fs.closeSync(fd); }
  #|}

///|
/// Same-filesystem hard-link publication refuses existing paths, including symlinks.
extern "js" fn write_file(name : String, data : Bytes) -> Bool =
  #|(name, data) => {
  #|  const fs = require('node:fs'), path = require('node:path'), zlib = require('node:zlib');
  #|  let temp, file;
  #|  try {
  #|    const dest = path.resolve(name);
  #|    temp = fs.mkdtempSync(path.join(path.dirname(dest), '.moonnifti-'));
  #|    file = path.join(temp, 'image');
  #|    const bytes = name.toLowerCase().endsWith('.gz') ? zlib.gzipSync(data) : data;
  #|    fs.writeFileSync(file, bytes, {flag:'wx', mode:0o600});
  #|    fs.linkSync(file, dest);
  #|    return true;
  #|  } catch (_) { return false; }
  #|  finally {
  #|    if (file) {try {fs.unlinkSync(file);} catch (_) {}}
  #|    if (temp) {try {fs.rmdirSync(temp);} catch (_) {}}
  #|  }
  #|}

///|
extern "js" fn exit_code(code : Int) -> Unit =
  #|(code) => {process.exitCode = code;}

///|
extern "js" fn report_error(message : String) -> Unit =
  #|(message) => {process.stderr.write(message+'\n'); process.exitCode = 1;}
