using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;

public static class ProductionSharedAtlasGenerator
{
    private const int Cell = 128;
    private static readonly Color Ink = Color.FromArgb(255, 8, 15, 25);
    private static readonly Color Ivory = Color.FromArgb(255, 237, 228, 208);
    private static readonly Color[] Accents = {
        Color.FromArgb(255, 55, 214, 190), Color.FromArgb(255, 244, 177, 72),
        Color.FromArgb(255, 144, 112, 255), Color.FromArgb(255, 239, 89, 122),
        Color.FromArgb(255, 106, 181, 255), Color.FromArgb(255, 135, 201, 91),
        Color.FromArgb(255, 245, 224, 105), Color.FromArgb(255, 207, 120, 232)
    };

    public static void Generate(string outputDirectory)
    {
        Directory.CreateDirectory(outputDirectory);
        GenerateAtlas(Path.Combine(outputDirectory, "trait.png"), 0);
        GenerateAtlas(Path.Combine(outputDirectory, "ability.png"), 1);
        GenerateAtlas(Path.Combine(outputDirectory, "status_damage.png"), 2);
        GenerateAtlas(Path.Combine(outputDirectory, "combat_vfx.png"), 3);
        GenerateAtlas(Path.Combine(outputDirectory, "core_ui.png"), 4);
    }

    private static void GenerateAtlas(string path, int atlasKind)
    {
        using (var bitmap = new Bitmap(1024, 1024, PixelFormat.Format32bppArgb))
        using (var graphics = Graphics.FromImage(bitmap))
        {
            graphics.Clear(Color.Transparent);
            graphics.SmoothingMode = SmoothingMode.None;
            graphics.InterpolationMode = InterpolationMode.NearestNeighbor;
            graphics.PixelOffsetMode = PixelOffsetMode.Half;
            for (int index = 0; index < 64; index++)
            {
                int row = index / 8;
                int column = index % 8;
                int x = column * Cell;
                int y = row * Cell;
                DrawCell(graphics, atlasKind, row, column, x, y);
            }
            bitmap.Save(path, ImageFormat.Png);
        }
    }

    private static void DrawCell(Graphics g, int atlasKind, int family, int variant, int x, int y)
    {
        Color accent = Accents[(variant + atlasKind * 2) % Accents.Length];
        using (var outline = new Pen(Ink, 11))
        using (var color = new Pen(accent, 7))
        using (var ivory = new Pen(Ivory, 4))
        using (var fill = new SolidBrush(accent))
        using (var ivoryFill = new SolidBrush(Ivory))
        {
            outline.StartCap = outline.EndCap = LineCap.Square;
            color.StartCap = color.EndCap = LineCap.Square;
            int cx = x + 64;
            int cy = y + 58;
            if (atlasKind == 0) DrawTrait(g, family, cx, cy, outline, color, fill);
            else if (atlasKind == 1) DrawAbility(g, family, cx, cy, outline, color, fill);
            else if (atlasKind == 2) DrawStatus(g, family, cx, cy, outline, color, fill);
            else if (atlasKind == 3) DrawVfx(g, family, cx, cy, outline, color, fill);
            else DrawUi(g, family, cx, cy, outline, color, fill);

            int markerCount = (variant % 4) + 1;
            for (int marker = 0; marker < markerCount; marker++)
            {
                int mx = cx - ((markerCount - 1) * 9) + marker * 18;
                g.FillRectangle(ivoryFill, mx - 4, y + 106, 8, 8);
            }
            if (variant >= 4)
                g.DrawRectangle(ivory, x + 18, y + 18, 92, 82);
        }
    }

    private static void DrawTrait(Graphics g, int family, int cx, int cy, Pen o, Pen c, Brush f)
    {
        switch (family)
        {
            case 0: Polygon(g, o, c, new[] { P(cx,cy-38),P(cx+34,cy-24),P(cx+28,cy+18),P(cx,cy+40),P(cx-28,cy+18),P(cx-34,cy-24) }); break;
            case 1: g.DrawEllipse(o,cx-34,cy-38,58,74); g.DrawEllipse(c,cx-34,cy-38,58,74); g.DrawLine(c,cx-20,cy+28,cx+26,cy-30); break;
            case 2: Polygon(g,o,c,new[]{P(cx,cy-42),P(cx+12,cy-12),P(cx+30,cy-24),P(cx+24,cy+26),P(cx,cy+42),P(cx-26,cy+24),P(cx-18,cy-10)}); break;
            case 3: Snowflake(g,c,cx,cy,38); break;
            case 4: Gear(g,o,c,cx,cy,30); break;
            case 5: g.DrawArc(o,cx-38,cy-40,72,78,55,260); g.DrawArc(c,cx-38,cy-40,72,78,55,260); g.DrawArc(c,cx-18,cy-28,48,54,80,220); break;
            case 6: Polygon(g,o,c,new[]{P(cx-38,cy+28),P(cx-32,cy-20),P(cx-10,cy),P(cx,cy-34),P(cx+12,cy),P(cx+34,cy-20),P(cx+38,cy+28)}); break;
            default: CrossedBlades(g,o,c,cx,cy); break;
        }
    }

    private static void DrawAbility(Graphics g, int family, int cx, int cy, Pen o, Pen c, Brush f)
    {
        switch (family)
        {
            case 0: Sword(g,o,c,cx,cy); break;
            case 1: Arrow(g,o,c,cx-34,cy+22,cx+38,cy-24); break;
            case 2: g.FillRectangle(new SolidBrush(Ink),cx-15,cy-40,30,80); g.FillRectangle(new SolidBrush(Ink),cx-40,cy-15,80,30); g.FillRectangle(f,cx-9,cy-34,18,68); g.FillRectangle(f,cx-34,cy-9,68,18); break;
            case 3: Polygon(g,o,c,new[]{P(cx,cy-40),P(cx+34,cy-22),P(cx+24,cy+24),P(cx,cy+42),P(cx-24,cy+24),P(cx-34,cy-22)}); break;
            case 4: Polygon(g,o,c,new[]{P(cx+8,cy-42),P(cx-28,cy+4),P(cx-4,cy+4),P(cx-14,cy+42),P(cx+30,cy-10),P(cx+6,cy-10)}); break;
            case 5: g.DrawEllipse(o,cx-40,cy-32,80,64); g.DrawEllipse(c,cx-40,cy-32,80,64); g.DrawEllipse(c,cx-22,cy-18,44,36); break;
            case 6: Diamond(g,o,c,cx,cy,38); g.DrawLine(c,cx,cy-38,cx,cy+38); break;
            default: Arrow(g,o,c,cx-40,cy-16,cx,cy-16); Arrow(g,o,c,cx,cy+18,cx+40,cy+18); break;
        }
    }

    private static void DrawStatus(Graphics g, int family, int cx, int cy, Pen o, Pen c, Brush f)
    {
        switch (family)
        {
            case 0: Heart(g,o,c,cx,cy); break;
            case 1: Polygon(g,o,c,new[]{P(cx,cy-38),P(cx+32,cy-20),P(cx+24,cy+28),P(cx,cy+40),P(cx-24,cy+28),P(cx-32,cy-20)}); g.DrawLine(c,cx-8,cy-30,cx+8,cy+30); break;
            case 2: DrawTrait(g,2,cx,cy,o,c,f); break;
            case 3: Snowflake(g,c,cx,cy,38); break;
            case 4: Drop(g,o,c,cx,cy); g.FillEllipse(f,cx+24,cy+18,12,12); break;
            case 5: Star(g,o,c,cx,cy,40,18); break;
            case 6: Drop(g,o,c,cx-18,cy); Drop(g,o,c,cx+20,cy+10); break;
            default: Arrow(g,o,c,cx-34,cy+20,cx+24,cy-22); Arrow(g,o,c,cx-14,cy+34,cx+42,cy-10); break;
        }
    }

    private static void DrawVfx(Graphics g, int family, int cx, int cy, Pen o, Pen c, Brush f)
    {
        switch (family)
        {
            case 0: g.DrawArc(o,cx-42,cy-34,84,68,205,120); g.DrawArc(c,cx-42,cy-34,84,68,205,120); break;
            case 1: Star(g,o,c,cx,cy,42,12); break;
            case 2: Arrow(g,o,c,cx-42,cy,cx+42,cy); break;
            case 3: g.DrawEllipse(o,cx-42,cy-24,84,48); g.DrawEllipse(c,cx-42,cy-24,84,48); break;
            case 4: g.DrawLine(o,cx-42,cy+22,cx+38,cy-20); g.DrawLine(c,cx-42,cy+22,cx+38,cy-20); g.DrawLine(c,cx-34,cy+34,cx+20,cy+4); break;
            case 5: for(int i=0;i<6;i++){double a=i*Math.PI/3;g.FillRectangle(f,cx+(int)(Math.Cos(a)*34)-4,cy+(int)(Math.Sin(a)*30)-4,8,8);} break;
            case 6: g.DrawEllipse(c,cx-36,cy,34,28); g.DrawEllipse(c,cx-8,cy-26,42,38); g.DrawEllipse(c,cx+8,cy+6,30,24); break;
            default: for(int i=-2;i<=2;i++) Polygon(g,o,c,new[]{P(cx+i*16-7,cy+34),P(cx+i*16,cy-34-(Math.Abs(i)*5)),P(cx+i*16+7,cy+34)}); break;
        }
    }

    private static void DrawUi(Graphics g, int family, int cx, int cy, Pen o, Pen c, Brush f)
    {
        switch (family)
        {
            case 0: g.DrawEllipse(o,cx-34,cy-34,68,68); g.DrawEllipse(c,cx-34,cy-34,68,68); g.DrawLine(c,cx,cy-22,cx,cy+22); break;
            case 1: g.DrawArc(o,cx-28,cy-42,56,34,180,180); g.DrawRectangle(o,cx-36,cy-24,72,64); g.DrawArc(c,cx-28,cy-42,56,34,180,180); g.DrawRectangle(c,cx-36,cy-24,72,64); break;
            case 2: g.DrawArc(o,cx-38,cy-38,76,76,35,280); g.DrawArc(c,cx-38,cy-38,76,76,35,280); Arrow(g,o,c,cx+18,cy-34,cx+40,cy-20); break;
            case 3: g.DrawRectangle(o,cx-34,cy-10,68,50); g.DrawRectangle(c,cx-34,cy-10,68,50); g.DrawArc(c,cx-24,cy-42,48,52,180,180); break;
            case 4: Star(g,o,c,cx,cy,42,19); break;
            case 5: Arrow(g,o,c,cx-40,cy,cx+36,cy); Arrow(g,o,c,cx-12,cy+28,cx+36,cy); break;
            case 6: Polygon(g,o,c,new[]{P(cx-42,cy+30),P(cx-30,cy-12),P(cx,cy-38),P(cx+30,cy-12),P(cx+42,cy+30)}); g.DrawLine(c,cx,cy-30,cx,cy+30); break;
            default: g.DrawLine(o,cx-34,cy+34,cx+28,cy-28); g.DrawLine(c,cx-34,cy+34,cx+28,cy-28); g.DrawRectangle(c,cx-40,cy+22,26,20); g.DrawLine(c,cx+12,cy-38,cx+38,cy-12); break;
        }
    }

    private static Point P(int x,int y){return new Point(x,y);}
    private static void Polygon(Graphics g, Pen o, Pen c, Point[] p){g.DrawPolygon(o,p);g.DrawPolygon(c,p);}
    private static void Arrow(Graphics g,Pen o,Pen c,int x1,int y1,int x2,int y2){g.DrawLine(o,x1,y1,x2,y2);g.DrawLine(c,x1,y1,x2,y2);double a=Math.Atan2(y2-y1,x2-x1);Point p1=P(x2-(int)(Math.Cos(a-.6)*22),y2-(int)(Math.Sin(a-.6)*22));Point p2=P(x2-(int)(Math.Cos(a+.6)*22),y2-(int)(Math.Sin(a+.6)*22));Polygon(g,o,c,new[]{P(x2,y2),p1,p2});}
    private static void Snowflake(Graphics g,Pen c,int cx,int cy,int r){for(int i=0;i<6;i++){double a=i*Math.PI/3;g.DrawLine(c,cx,cy,cx+(int)(Math.Cos(a)*r),cy+(int)(Math.Sin(a)*r));}}
    private static void Gear(Graphics g,Pen o,Pen c,int cx,int cy,int r){g.DrawEllipse(o,cx-r,cy-r,r*2,r*2);g.DrawEllipse(c,cx-r,cy-r,r*2,r*2);g.DrawEllipse(c,cx-10,cy-10,20,20);for(int i=0;i<8;i++){double a=i*Math.PI/4;g.DrawLine(c,cx+(int)(Math.Cos(a)*r),cy+(int)(Math.Sin(a)*r),cx+(int)(Math.Cos(a)*(r+14)),cy+(int)(Math.Sin(a)*(r+14)));}}
    private static void CrossedBlades(Graphics g,Pen o,Pen c,int cx,int cy){g.DrawLine(o,cx-34,cy+34,cx+32,cy-32);g.DrawLine(o,cx+34,cy+34,cx-32,cy-32);g.DrawLine(c,cx-34,cy+34,cx+32,cy-32);g.DrawLine(c,cx+34,cy+34,cx-32,cy-32);}
    private static void Sword(Graphics g,Pen o,Pen c,int cx,int cy){g.DrawLine(o,cx-28,cy+30,cx+30,cy-30);g.DrawLine(c,cx-28,cy+30,cx+30,cy-30);g.DrawLine(c,cx-28,cy+10,cx-8,cy+30);}
    private static void Diamond(Graphics g,Pen o,Pen c,int cx,int cy,int r){Polygon(g,o,c,new[]{P(cx,cy-r),P(cx+r,cy),P(cx,cy+r),P(cx-r,cy)});}
    private static void Heart(Graphics g,Pen o,Pen c,int cx,int cy){Point[] p={P(cx,cy+38),P(cx-38,cy-6),P(cx-28,cy-30),P(cx,cy-12),P(cx+28,cy-30),P(cx+38,cy-6)};Polygon(g,o,c,p);}
    private static void Drop(Graphics g,Pen o,Pen c,int cx,int cy){Polygon(g,o,c,new[]{P(cx,cy-40),P(cx+28,cy+10),P(cx+16,cy+34),P(cx-16,cy+34),P(cx-28,cy+10)});}
    private static void Star(Graphics g,Pen o,Pen c,int cx,int cy,int ro,int ri){Point[] p=new Point[10];for(int i=0;i<10;i++){double a=-Math.PI/2+i*Math.PI/5;int r=(i%2==0)?ro:ri;p[i]=P(cx+(int)(Math.Cos(a)*r),cy+(int)(Math.Sin(a)*r));}Polygon(g,o,c,p);}
}
