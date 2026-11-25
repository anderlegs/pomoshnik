from PIL import Image, ImageDraw
S=1024
img=Image.new('RGB',(S,S))
d=ImageDraw.Draw(img)
for y in range(S):
    t=y/S*0.6
    d.line([(0,y),(S,y)],fill=(int(0x16+0x70*t),int(0xA9+0x32*t),int(0xEC+0x0F*t)))
d.polygon([(0,S),(0,720),(220,560),(380,680),(560,500),(760,660),(900,580),(S,650),(S,S)],fill=(0x2C,0x7F,0xA6))
d.polygon([(0,S),(0,840),(180,760),(360,830),(520,740),(700,820),(880,760),(S,800),(S,S)],fill=(0x1B,0x58,0x75))
d.ellipse([292,170,732,610],fill='white')
d.line([(400,400),(480,480),(630,310)],fill=(0x1E,0xB8,0xF5),width=56,joint='curve')
img.save('App/Assets.xcassets/AppIcon.appiconset/icon.png')
