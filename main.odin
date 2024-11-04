package text_render

import "core:fmt"
import "core:math"
import "core:image"
import "core:os"
import "core:unicode/utf8"
import "core:bytes"
import "core:image/netpbm"
import "core:image/qoi"
import "core:mem"

import rl "vendor:raylib"
import stbtt "vendor:stb/truetype"

KERNING_ENABLED :: #config(bool, false)

FONT :: #load("jetbrains_mono.ttf", []byte)

Font_Info :: stbtt.fontinfo

Store_Key :: struct {
	codepoint: rune,
	size: i32,
}

Glyph_Store :: struct {
	glyphs: map[Store_Key]Glyph_Data,
	_font_info: Font_Info,
}

Box :: struct {
	x0, x1: i32,
	y0, y1: i32,
}

Glyph_Data :: struct {
	using box: Box,
	data: []byte,
	left_side_bearing: i32,
	advance_width: i32,
}

store_make :: proc(font: Font_Info) -> Glyph_Store {
	glyphs := make_map(map[Store_Key]Glyph_Data)
	store := Glyph_Store {
		glyphs = glyphs,
		_font_info = font,
	}
	return store
}

render_string_to_bitmap :: proc(store: ^Glyph_Store, text: string, origin: [2]i32, size: i32, out: ^Bitmap){
	scale := scale_for_pixel_height(&store._font_info, f32(size))
	ascent, descent, line_gap := get_font_vmetrics(&store._font_info)

	ascent = auto_cast math.round(f32(ascent) * scale)
	descent = auto_cast math.round(f32(descent) * scale)

	x_offset := origin.x
	line_offset := i32(0)
	for r, i in text {
		if r == '\n' {
			x_offset = origin.x
			line_offset += size
			continue
		}

		glyph_data := store_get_codepoint(store, r, size)
		adv_width, lsb := glyph_data.advance_width, glyph_data.left_side_bearing

		bitmap := Bitmap {
			data = glyph_data.data,
			width = int(glyph_data.x1 - glyph_data.x0),
			height = int(glyph_data.y1 - glyph_data.y0),
		}

		y_offset := ascent + glyph_data.box.y0 + i32(origin.y) + i32(line_offset)

		bitmap_copy(out, bitmap, x_offset, y_offset)

		x_offset += auto_cast math.round(f32(adv_width) * scale)

		when KERNING_ENABLED {
			if i != len(text){
				next, _ := utf8.decode_rune(text[i:])
				kern := stbtt.GetCodepointKernAdvance(&store._font_info, r, next)
				x_offset += auto_cast math.round(f32(kern) * scale)
			}
		}
	}
}

glyph_dimensions :: proc(bitmap: Glyph_Data) -> (w: i32, h: i32) {
	w = bitmap.box.x1 - bitmap.box.x0
	h = bitmap.box.y1 - bitmap.box.y0
	return
}

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

render_codepoint_bitmap :: proc(font_info: ^Font_Info, point: rune, scale: f32) -> (bitmap: Glyph_Data, err: mem.Allocator_Error){
	bitmap.box = get_codepoint_bitmap_box(font_info, point, scale)
	adv_width, lsb := get_codepoint_hmetrics(font_info, point)

	w, h := glyph_dimensions(bitmap)
	data := make([]byte, w * h) or_return

	stbtt.MakeCodepointBitmap(font_info,
		raw_data(data),
		w, h,
		w,
		scale, scale, point)

	bitmap.data = data
	bitmap.left_side_bearing = lsb
	bitmap.advance_width = adv_width
	return
}

store_get_codepoint :: proc(store: ^Glyph_Store, point: rune, size: i32) -> Glyph_Data {
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

bitmap_copy :: proc(dest: ^Bitmap, source: Bitmap, #any_int x, y: int){
	for row in 0..<source.height {
		mem.copy(
			&dest.data[x + ((row + y) * dest.width)],
			&source.data[row * source.width],
			source.width,
		)
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
	font_info : Font_Info
	if !stbtt.InitFont(&font_info, raw_data(FONT), 0){
		fmt.panicf("Failed to load font")
	}

	handle, _ := os.open("out.pbm", os.O_WRONLY | os.O_CREATE, 0o644)
	defer os.close(handle)

	bitmap := bitmap_make(800, 600)
	// mem.set(&bitmap.data[0], 0x3f, bitmap.width * bitmap.height)
	store := store_make(font_info)
	render_string_to_bitmap(&store,
		`int main(){
    printf("click click");
}`,
		{20, 10}, 16 * 4, &bitmap)

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
