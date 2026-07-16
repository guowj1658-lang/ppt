param(
    [Parameter(Mandatory = $true)]
    [string[]]$Paths
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$source = @'
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;
using System.Runtime.InteropServices;

public static class CheckerboardBackgroundRemover
{
    private static bool IsBackgroundCandidate(byte[] pixels, int stride, int x, int y)
    {
        int offset = y * stride + x * 4;
        int b = pixels[offset];
        int g = pixels[offset + 1];
        int r = pixels[offset + 2];
        int min = Math.Min(r, Math.Min(g, b));
        int max = Math.Max(r, Math.Max(g, b));
        // The generated checkerboard is very light and nearly neutral. Keep
        // this match deliberately tight so white clothing cannot become a
        // path for the border flood-fill.
        return min >= 232 && max - min <= 16;
    }

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

            int width = image.Width;
            int height = image.Height;
            int pixelCount = checked(width * height);
            var rect = new Rectangle(0, 0, width, height);
            var data = image.LockBits(rect, ImageLockMode.ReadWrite, PixelFormat.Format32bppArgb);
            int stride = data.Stride;
            byte[] pixels = new byte[stride * height];
            Marshal.Copy(data.Scan0, pixels, 0, pixels.Length);

            bool[] background = new bool[pixelCount];
            int[] queue = new int[pixelCount];
            int head = 0;
            int tail = 0;

            Action<int, int> seed = (x, y) =>
            {
                int index = y * width + x;
                if (!background[index] && IsBackgroundCandidate(pixels, stride, x, y))
                {
                    background[index] = true;
                    queue[tail++] = index;
                }
            };

            for (int x = 0; x < width; x++)
            {
                seed(x, 0);
                seed(x, height - 1);
            }
            for (int y = 1; y < height - 1; y++)
            {
                seed(0, y);
                seed(width - 1, y);
            }

            while (head < tail)
            {
                int index = queue[head++];
                int x = index % width;
                int y = index / width;
                if (x > 0) seed(x - 1, y);
                if (x + 1 < width) seed(x + 1, y);
                if (y > 0) seed(x, y - 1);
                if (y + 1 < height) seed(x, y + 1);
            }

            int[] labels = new int[pixelCount];
            for (int i = 0; i < pixelCount; i++) labels[i] = background[i] ? -2 : -1;
            var componentSizes = new List<int>();
            int component = 0;

            for (int start = 0; start < pixelCount; start++)
            {
                if (labels[start] != -1) continue;
                head = 0;
                tail = 0;
                labels[start] = component;
                queue[tail++] = start;
                int size = 0;

                while (head < tail)
                {
                    int index = queue[head++];
                    size++;
                    int x = index % width;
                    int y = index / width;

                    if (x > 0 && labels[index - 1] == -1) { labels[index - 1] = component; queue[tail++] = index - 1; }
                    if (x + 1 < width && labels[index + 1] == -1) { labels[index + 1] = component; queue[tail++] = index + 1; }
                    if (y > 0 && labels[index - width] == -1) { labels[index - width] = component; queue[tail++] = index - width; }
                    if (y + 1 < height && labels[index + width] == -1) { labels[index + width] = component; queue[tail++] = index + width; }
                }

                componentSizes.Add(size);
                component++;
            }

            int largestComponent = 0;
            for (int i = 1; i < componentSizes.Count; i++)
            {
                if (componentSizes[i] > componentSizes[largestComponent]) largestComponent = i;
            }

            for (int y = 0; y < height; y++)
            {
                for (int x = 0; x < width; x++)
                {
                    int index = y * width + x;
                    int offset = y * stride + x * 4;
                    if (x > width * 0.72 && y > height * 0.89)
                    {
                        pixels[offset + 3] = 0;
                        continue;
                    }
                    if (labels[index] != largestComponent)
                    {
                        pixels[offset + 3] = 0;
                        continue;
                    }

                    bool touchesTransparent =
                        x == 0 || y == 0 || x + 1 == width || y + 1 == height ||
                        labels[index - 1] != largestComponent ||
                        labels[index + 1] != largestComponent ||
                        labels[index - width] != largestComponent ||
                        labels[index + width] != largestComponent;

                    if (touchesTransparent)
                    {
                        int b = pixels[offset];
                        int g = pixels[offset + 1];
                        int r = pixels[offset + 2];
                        int min = Math.Min(r, Math.Min(g, b));
                        int max = Math.Max(r, Math.Max(g, b));
                        if (min > 188 && max - min < 42)
                        {
                            pixels[offset + 3] = (byte)Math.Max(24, Math.Min(232, (255 - min) * 4));
                        }
                    }
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
    [CheckerboardBackgroundRemover]::Remove($resolved)
    Write-Output "Background removed: $resolved"
}
