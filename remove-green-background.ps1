param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class GreenBackgroundRemover
{
    public static void Remove(string inputPath)
    {
        string temporary = inputPath + ".transparent.png";
        using (var source = new Bitmap(inputPath))
        using (var image = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(image))
            {
                graphics.DrawImageUnscaled(source, 0, 0);
            }

            var rect = new Rectangle(0, 0, image.Width, image.Height);
            var data = image.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int stride = data.Stride;
            byte[] pixels = new byte[stride * image.Height];
            Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);

            for (int y = 0; y < image.Height; y++)
            {
                for (int x = 0; x < image.Width; x++)
                {
                    int offset = y * stride + x * 4;
                    int b = pixels[offset];
                    int g = pixels[offset + 1];
                    int r = pixels[offset + 2];
                    int other = Math.Max(r, b);
                    int dominance = g - other;

                    int alpha = 255;
                    if (g > 105 && dominance >= 92) alpha = 0;
                    else if (g > 90 && dominance > 32)
                    {
                        alpha = 255 - (dominance - 32) * 255 / 60;
                        alpha = Math.Max(0, Math.Min(255, alpha));
                    }

                    if (dominance > 8)
                    {
                        int despilled = Math.Min(g, other + 8);
                        pixels[offset + 1] = (byte)despilled;
                    }
                    pixels[offset + 3] = (byte)alpha;
                }
            }

            Marshal.Copy(pixels, 0, data.Scan0, pixels.Length);
            image.UnlockBits(data);
            image.Save(temporary, ImageFormat.Png);
        }

        File.Copy(temporary, inputPath, true);
        File.Delete(temporary);
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing

foreach ($path in $Paths) {
    $resolved = (Resolve-Path -LiteralPath $path).Path
    [GreenBackgroundRemover]::Remove($resolved)
    Write-Output "Green background removed: $resolved"
}
