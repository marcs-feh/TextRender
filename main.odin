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

scale_for_pixel_height :: stbtt.ScaleForPixelHeight

main :: proc(){
	font_info : Font_Info
	if !stbtt.InitFont(&font_info, raw_data(FONT), 0){
		fmt.panicf("Failed to load font")
	}

	scale := scale_for_pixel_height(&font_info, 24)
	ascent, descent, line_gap := get_font_vmetrics(&font_info)

	ascent = i32(math.round(f32(ascent) * scale))
	descent = i32(math.round(f32(descent) * scale))

	bitmap, err := render_codepoint_bitmap(&font_info, '9', scale)

	handle, _ := os.open("out.pbm", os.O_WRONLY | os.O_CREATE, 0o644)
	defer os.close(handle)

	width, height := glyph_dimensions(bitmap)
	os.write(handle, transmute([]byte)fmt.tprintf("P5\n%v %v\n%v\n", width, height, 255))
	os.write(handle, bitmap.data)
	fmt.println("IMG WRITE")
}
