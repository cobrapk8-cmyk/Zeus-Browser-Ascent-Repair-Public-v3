"""Exercise the same native region decoder on PNG/JPEG/WebP and malformed input."""
import ctypes, io, pathlib, random, sys, unittest
from PIL import Image, ImageChops
lib=ctypes.CDLL(sys.argv.pop(1))
lib.zeus_comic_decode_region.argtypes=[ctypes.POINTER(ctypes.c_ubyte),ctypes.c_ulong,*([ctypes.c_int]*4)]
lib.zeus_comic_decode_region.restype=ctypes.POINTER(ctypes.c_ubyte)
lib.zeus_comic_free_pixels.argtypes=[ctypes.POINTER(ctypes.c_ubyte)]
def decode(data,width,y,height):
    source=(ctypes.c_ubyte*len(data)).from_buffer_copy(data)
    p=lib.zeus_comic_decode_region(source,len(data),0,y,width,height)
    if not p:return None
    try:return Image.frombytes('RGBA',(width,height),ctypes.string_at(p,width*height*4))
    finally:lib.zeus_comic_free_pixels(p)
class RegionDecoderTests(unittest.TestCase):
    def test_regions_match_original_pixels_in_all_formats(self):
        random.seed(7)
        image=Image.new('RGB',(120,300));image.putdata([(random.randrange(256),random.randrange(256),random.randrange(256))for _ in range(120*300)])
        for kind in ['PNG','JPEG','WEBP']:
            with self.subTest(format=kind):
                output=io.BytesIO();image.save(output,format=kind);data=output.getvalue();reference=Image.open(io.BytesIO(data)).convert('RGBA')
                for y in [0,1,75,199]:
                    region=decode(data,120,y,100);self.assertIsNotNone(region)
                    self.assertIsNone(ImageChops.difference(region,reference.crop((0,y,120,y+100))).getbbox())
    def test_very_tall_image_keeps_source_resolution(self):
        image=Image.new('RGB',(300,40000),(111,77,31));output=io.BytesIO();image.save(output,format='PNG');region=decode(output.getvalue(),300,39000,1000)
        self.assertEqual(region.size,(300,1000));self.assertEqual(region.getpixel((42,542)),(111,77,31,255))
    def test_invalid_bounds_and_malformed_input_are_rejected(self):
        output=io.BytesIO();Image.new('RGB',(120,300)).save(output,format='PNG');data=output.getvalue()
        for width,y,height in [(120,-1,20),(120,295,20),(121,0,20),(16384,0,1000)]:self.assertIsNone(decode(data,width,y,height))
        for data in [b'bad',b'\x89PNG\r\n\x1a\n'+b'\x00'*50,b'\xff\xd8'+b'x'*100]:self.assertIsNone(decode(data,120,0,20))
unittest.main()
