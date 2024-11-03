package text_render

import "core:fmt"
import "core:math"
import "core:image"
import "core:os"
import "core:bytes"
import "core:image/netpbm"
import "core:image/qoi"
import "core:mem"

import rl "vendor:raylib"
import stbtt "vendor:stb/truetype"

FONT :: #load("inria_sans.ttf", []byte)

Store_Key :: struct {
	codepoint: rune,
	size: i32,
}

Glyph_Store :: struct {
	atlas_width: uint,
	atlas_height: uint,
	glyphs: map[Store_Key]Glyph_Bitmap,
	_font_info: Font_Info,
}

store_make :: proc(font: Font_Info) -> Glyph_Store {
	glyphs := make_map(map[Store_Key]Glyph_Bitmap)
	store := Glyph_Store {
		glyphs = glyphs,
		_font_info = font,
	}
	return store
}

// render_string_to_bitmap :: proc(store: ^Glyph_Store, text: string, size: i32, out: ^Glyph_Bitmap){
// 	x := 0
// 	scale := scale_for_pixel_height(&store._font_info, f32(size))
// 	ascent, descent, line_gap := get_font_vmetrics(&store._font_info)
//
// 	for r in text {
// 		bitmap := store_get_codepoint(store, r, size)
// 		adv_width, lsb := get_codepoint_hmetrics(&store._font_info, 'A')
// 		y := ascent + bitmap.box.y1
// 		width, height := glyph_dimensions(bitmap)
// 		byte_offset := x + int(math.round(f32(lsb) * scale)) + int(y * width)
//
// 		// for row in 0..<height {
// 		// 	mem.copy_non_overlapping(&out.data[byte_offset], &bitmap.data[row * width], bitmap.width)
// 		// }
// 	}
// }

Box :: struct {
	x0, x1: i32,
	y0, y1: i32,
}

Glyph_Bitmap :: struct {
	box: Box,
	data: []byte,
}

glyph_dimensions :: proc(bitmap: Glyph_Bitmap) -> (w: i32, h: i32) {
	w = bitmap.box.x1 - bitmap.box.x0
	h = bitmap.box.y1 - bitmap.box.y0
	return
}

Font_Info :: stbtt.fontinfo

get_font_vmetrics :: proc(font_info: ^Font_Info) -> (ascent: i32, descent: i32, line_gap: i32){
	stbtt.GetFontVMetrics(font_info, &ascent, &descent, &line_gap)
	return
}

get_codepoint_hmetrics :: proc(font_info: ^Font_Info, point: rune) -> (advance_width, left_side_bearing: i32){
	stbtt.GetCodepointHMetrics(font_info, point, &advance_width, &left_side_bearing)
	return
}

get_codepoint_bitmap_box :: proc(font_info: ^Font_Info, point: rune, scale: f32) -> (box: Box){
	stbtt.GetCodepointBitmapBox(font_info, point, scale, scale, &box.x0, &box.y0, &box.x1, &box.y1)
	return
}

Image :: image.Image

render_codepoint_bitmap :: proc(font_info: ^Font_Info, point: rune, scale: f32) -> (bitmap: Glyph_Bitmap, err: mem.Allocator_Error){
	bitmap.box = get_codepoint_bitmap_box(font_info, point, scale)
	w, h := glyph_dimensions(bitmap)
	data := make([]byte, w * h) or_return

	stbtt.MakeCodepointBitmap(font_info,
		raw_data(data),
		w, h,
		w,
		scale, scale, point)

	bitmap.data = data
	return
}

store_get_codepoint :: proc(store: ^Glyph_Store, point: rune, size: i32) -> Glyph_Bitmap {
	bitmap, ok := store.glyphs[{point, size}]
	if !ok {
		scale := scale_for_pixel_height(&store._font_info, f32(size))
		bitmap, _ = render_codepoint_bitmap(&store._font_info, point, scale)
		store.glyphs[{point, size}] = bitmap
	}
	return bitmap
}

scale_for_pixel_height :: stbtt.ScaleForPixelHeight

Bitmap :: struct {
	data: []byte,
	width, height: int,
}

bitmap_copy :: proc(dest: ^Bitmap, source: Bitmap, x, y: int){
	// dest.data[x + (y * dest.width)] = source.data[0]
	for row in 0..<source.height {
		mem.copy(&dest.data[x + ((row + y) * dest.width)], &source.data[row * source.width], source.width)
	}
}

bitmap_make :: proc(w, h: int) -> Bitmap {
	data := make([]byte, w * h)
	return Bitmap {
		data = data,
		width = w, height = h,
	}
}

main :: proc(){
	// font_info : Font_Info
	// if !stbtt.InitFont(&font_info, raw_data(FONT), 0){
	// 	fmt.panicf("Failed to load font")
	// }
	//
	// scale := scale_for_pixel_height(&font_info, 24 * 4)
	// ascent, descent, line_gap := get_font_vmetrics(&font_info)
	//
	// ascent = i32(math.round(f32(ascent) * scale))
	// descent = i32(math.round(f32(descent) * scale))

	handle, _ := os.open("out.pbm", os.O_WRONLY | os.O_CREATE, 0o644)
	defer os.close(handle)

	bitmap := bitmap_make(400, 300)
	mem.set(&bitmap.data[0], 0x3e, len(bitmap.data))

	bm_a := bitmap_make(120, 40)
	mem.set(&bm_a.data[0], 0xf1, len(bm_a.data))

	bitmap_copy(&bitmap, bm_a, 20, 200)
	save_image: {
		// width, height := glyph_dimensions(bitmap)
		using bitmap
		total_written : i64

		if n, err := os.write(handle, transmute([]byte)fmt.tprintf("P5\n%v %v\n%v\n", width, height, 255)); err == nil {
			total_written += i64(n)
		}
		if n, err := os.write(handle, bitmap.data); err == nil {
			total_written += i64(n)
		}

		fmt.printfln("Wrote %vB to out.pbm", total_written)
	}
}
