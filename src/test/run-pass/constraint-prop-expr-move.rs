
fn main() unsafe {
    let a: uint = 1u;
    let b: uint = 4u;
    let c: uint = 17u;
    check (uint::le(a, b));
    c <- a;
    log(debug, str::unsafe::slice_bytes_safe_range("kitties", c, b));
}
