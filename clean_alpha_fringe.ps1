param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths
)

Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class AlphaFringeCleaner
{
    public static void Clean(string path)
    {
        using (var source = new Bitmap(path))
        using (var image = new Bitmap(source.Width, source.Height, PixelFormat.Format32bppArgb))
        {
            using (var graphics = Graphics.FromImage(image))
            {
                graphics.DrawImageUnscaled(source, 0, 0);
            }

            var rect = new Rectangle(0, 0, image.Width, image.Height);
            var data = image.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int stride = data.Stride;
            byte[] input = new byte[stride * image.Height];
            Marshal.Copy(data.Scan0, input, 0, input.Length);
            byte[] output = (byte[])input.Clone();

            int width = image.Width;
            int height = image.Height;
            byte[] alpha = new byte[width * height];
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    alpha[y * width + x] = input[y * stride + x * 4 + 3];
                }
            }

            // Contract the matte by two pixels. This removes the opaque light halo,
            // then rebuilds a narrow antialiased transition on the new boundary.
            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    int offset = y * stride + x * 4;
                    int originalAlpha = alpha[y * width + x];
                    if (originalAlpha == 0) continue;

                    int minAlpha1 = 255;
                    int minAlpha2 = 255;
                    for (int dy = -2; dy <= 2; dy++)
                    {
                        int ny = y + dy;
                        if (ny < 0 || ny >= height)
                        {
                            minAlpha2 = 0;
                            continue;
                        }

                        for (int dx = -2; dx <= 2; dx++)
                        {
                            int nx = x + dx;
                            if (nx < 0 || nx >= width)
                            {
                                minAlpha2 = 0;
                                continue;
                            }

                            int distanceSquared = dx * dx + dy * dy;
                            int nearbyAlpha = alpha[ny * width + nx];
                            if (distanceSquared <= 1 && nearbyAlpha < minAlpha1) minAlpha1 = nearbyAlpha;
                            if (distanceSquared <= 4 && nearbyAlpha < minAlpha2) minAlpha2 = nearbyAlpha;
                        }
                    }

                    int newAlpha = originalAlpha;
                    if (minAlpha1 < 32)
                    {
                        newAlpha = 0;
                    }
                    else if (minAlpha2 < 32)
                    {
                        newAlpha = Math.Min(newAlpha, 118);
                    }
                    else if (minAlpha2 < 180)
                    {
                        newAlpha = Math.Min(newAlpha, 205);
                    }

                    if (newAlpha < originalAlpha)
                    {
                        // Remove pale/blue matte contamination from the remaining edge.
                        int b = input[offset];
                        int g = input[offset + 1];
                        int r = input[offset + 2];
                        int max = Math.Max(r, Math.Max(g, b));
                        int min = Math.Min(r, Math.Min(g, b));
                        bool pale = max > 150 && max - min < 95;
                        double darken = pale ? 0.72 : 0.88;
                        output[offset] = (byte)Math.Round(b * darken);
                        output[offset + 1] = (byte)Math.Round(g * darken);
                        output[offset + 2] = (byte)Math.Round(r * darken);
                        output[offset + 3] = (byte)newAlpha;
                    }
                }
            }

            Marshal.Copy(output, 0, data.Scan0, output.Length);
            image.UnlockBits(data);

            string backup = Path.Combine(
                Path.GetDirectoryName(path),
                Path.GetFileNameWithoutExtension(path) + ".before-fringe-clean.png"
            );
            if (!File.Exists(backup)) File.Copy(path, backup);

            string temp = path + ".tmp.png";
            image.Save(temp, ImageFormat.Png);
            File.Copy(temp, path, true);
            File.Delete(temp);
        }
    }
}
'@

Add-Type -TypeDefinition $source -ReferencedAssemblies System.Drawing

foreach ($path in $Paths) {
    [AlphaFringeCleaner]::Clean((Resolve-Path $path).Path)
    Write-Output "Cleaned: $path"
}
