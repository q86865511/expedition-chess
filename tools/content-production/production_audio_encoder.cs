using System;
using System.Collections.Generic;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;

public sealed class ProductionAudioEntry
{
    public string Token;
    public string Path;
    public string Sha256;
    public int SampleRate;
    public int Channels;
    public long Frames;
    public double DurationSeconds;
    public double TruePeakDbfs;
    public double LoopSeamRmsDbfs;
    public int LocalProcessingSeed;
    public bool IsMusic;
}

public static class ProductionAudioEncoder
{
    private const int SampleRate = 48000;
    private const int Channels = 2;
    private const int MusicSeconds = 24;
    private const double Quality = 0.5;
    private const int SeedBase = 0x47324155;
    private const int SfmRead = 0x10;
    private const int SfmWrite = 0x20;
    private const int FormatOggVorbis = 0x200000 | 0x0060;
    private const int SetCompressionLevel = 0x1301;
    private const double TruePeakTarget = 0.7079457843841379; // -3 dBFS.

    private static readonly string[] MusicTokens = {
        "menu", "camp", "expedition", "combat", "results"
    };
    private static readonly double[] MusicRoots = {
        55.0, 65.406, 73.416, 82.407, 61.735
    };
    private static readonly int[][] MusicIntervals = {
        new int[] {0, 4, 7, 11},
        new int[] {0, 3, 7, 10},
        new int[] {0, 5, 7, 12},
        new int[] {0, 2, 7, 10},
        new int[] {0, 4, 7, 12}
    };
    private static readonly string[] SfxTokens = {
        "ui_confirm", "ui_cancel", "ui_focus", "ui_error", "shop_buy",
        "shop_sell", "shop_refresh", "forge", "equip", "reward_select",
        "event_select", "combat_cast", "combat_melee_hit", "combat_defeat",
        "combat_shield", "combat_heal", "combat_death",
        "combat_ranged_attack", "combat_magic_hit", "combat_boss_warning",
        "combat_victory"
    };

    [StructLayout(LayoutKind.Sequential)]
    private struct SfInfo
    {
        public long frames;
        public int samplerate;
        public int channels;
        public int format;
        public int sections;
        public int seekable;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool SetDllDirectory(string lpPathName);

    [DllImport("libsndfile_x64.dll", CallingConvention = CallingConvention.Cdecl, CharSet = CharSet.Ansi)]
    private static extern IntPtr sf_open(string path, int mode, ref SfInfo info);

    [DllImport("libsndfile_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern long sf_writef_float(IntPtr sndfile, float[] ptr, long frames);

    [DllImport("libsndfile_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern long sf_readf_float(IntPtr sndfile, float[] ptr, long frames);

    [DllImport("libsndfile_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sf_command(IntPtr sndfile, int command, ref double data, int datasize);

    [DllImport("libsndfile_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern int sf_close(IntPtr sndfile);

    [DllImport("libsndfile_x64.dll", CallingConvention = CallingConvention.Cdecl)]
    private static extern IntPtr sf_strerror(IntPtr sndfile);

    public static ProductionAudioEntry[] Build(string repoRoot)
    {
        repoRoot = Path.GetFullPath(repoRoot);
        string dllDirectory = Path.Combine(
            repoRoot, ".pipeline", "content-production", "python-packages",
            "_soundfile_data"
        );
        if (!SetDllDirectory(dllDirectory))
            throw new InvalidOperationException("Could not load pinned libsndfile directory.");

        List<ProductionAudioEntry> entries = new List<ProductionAudioEntry>();
        for (int index = 0; index < MusicTokens.Length; index++)
        {
            string path = Path.Combine(
                repoRoot, "assets", "production", "audio", "music",
                MusicTokens[index] + ".ogg"
            );
            entries.Add(WriteAndInspect(
                path,
                MusicTokens[index],
                SynthesizeMusic(index),
                true,
                SeedBase + index
            ));
        }
        for (int index = 0; index < SfxTokens.Length; index++)
        {
            string path = Path.Combine(
                repoRoot, "assets", "production", "audio", "sfx",
                SfxTokens[index] + ".ogg"
            );
            entries.Add(WriteAndInspect(
                path,
                SfxTokens[index],
                SynthesizeSfx(index),
                false,
                SeedBase + 100 + index
            ));
        }
        return entries.ToArray();
    }

    private static float[] SynthesizeMusic(int index)
    {
        int frames = SampleRate * MusicSeconds;
        float[] samples = new float[frames * Channels];
        double phase = Math.PI * 2.0 * index / MusicTokens.Length;
        for (int frame = 0; frame < frames; frame++)
        {
            double time = (double)frame / SampleRate;
            double left = 0.0;
            double right = 0.0;
            for (int voice = 0; voice < MusicIntervals[index].Length; voice++)
            {
                double frequency = MusicRoots[index] * Math.Pow(
                    2.0, MusicIntervals[index][voice] / 12.0
                );
                double periodicFrequency = Math.Round(frequency * MusicSeconds) / MusicSeconds;
                double amplitude = 0.13 / Math.Pow(voice + 1.0, 0.55);
                left += amplitude * Math.Sin(Math.PI * 2.0 * periodicFrequency * time + phase);
                right += amplitude * Math.Sin(
                    Math.PI * 2.0 * periodicFrequency * time + phase + 0.18 * (voice + 1)
                );
            }
            double pulse = 0.82 + 0.18 * Math.Sin(Math.PI * 4.0 * time + phase);
            double shimmerFrequency = Math.Round(MusicRoots[index] * 4.0 * MusicSeconds) / MusicSeconds;
            double shimmer = 0.025 * Math.Sin(Math.PI * 2.0 * shimmerFrequency * time);
            samples[frame * 2] = (float)Math.Tanh((left + shimmer) * pulse * 1.15);
            samples[frame * 2 + 1] = (float)Math.Tanh((right - shimmer) * pulse * 1.15);
        }

        int seamFrames = (int)Math.Round(SampleRate * 0.05);
        int transitionStart = frames - seamFrames * 2;
        for (int frame = 0; frame < seamFrames; frame++)
        {
            double fade = (double)frame / seamFrames;
            for (int channel = 0; channel < Channels; channel++)
            {
                int transition = (transitionStart + frame) * 2 + channel;
                int opening = frame * 2 + channel;
                samples[transition] = (float)(samples[transition] * (1.0 - fade) + samples[opening] * fade);
                samples[(frames - seamFrames + frame) * 2 + channel] = samples[opening];
            }
        }
        Normalize(samples);
        return samples;
    }

    private static float[] SynthesizeSfx(int index)
    {
        double duration = 0.22 + (index % 5) * 0.055;
        int frames = (int)Math.Round(SampleRate * duration);
        double[] mono = new double[frames];
        uint state = unchecked((uint)(SeedBase + 100 + index));
        double phase = 0.0;
        double baseFrequency = 170.0 + index * 23.0;
        for (int frame = 0; frame < frames; frame++)
        {
            double time = (double)frame / SampleRate;
            double sweep = baseFrequency * (
                1.0 + (index % 2 == 0 ? 0.8 : -0.35) * time / duration
            );
            phase += Math.PI * 2.0 * sweep / SampleRate;
            state ^= state << 13;
            state ^= state >> 17;
            state ^= state << 5;
            double noise = ((state & 0xFFFFFF) / 8388607.5) - 1.0;
            double tonal = Math.Sin(phase) + 0.35 * Math.Sin(phase * 2.01);
            double attack = Math.Min(1.0, time / 0.008);
            double release = Math.Pow(Math.Max(0.0, 1.0 - time / duration), 1.8 + index % 3);
            double mix = (0.72 * tonal + 0.18 * noise) * attack * release;
            if (SfxTokens[index].StartsWith("combat_"))
                mix += 0.10 * Math.Sin(phase * 0.5) * release;
            mono[frame] = Math.Tanh(mix * 0.62);
        }
        int delay = 7 + index % 11;
        float[] samples = new float[frames * Channels];
        for (int frame = 0; frame < frames; frame++)
        {
            double delayed = frame >= delay ? mono[frame - delay] : 0.0;
            samples[frame * 2] = (float)mono[frame];
            samples[frame * 2 + 1] = (float)(0.94 * mono[frame] + 0.06 * delayed);
        }
        Normalize(samples);
        return samples;
    }

    private static void Normalize(float[] samples)
    {
        double peak = 0.0;
        for (int index = 0; index < samples.Length; index++)
            peak = Math.Max(peak, Math.Abs(samples[index]));
        if (peak <= TruePeakTarget)
            return;
        double scale = TruePeakTarget / peak;
        for (int index = 0; index < samples.Length; index++)
            samples[index] = (float)(samples[index] * scale);
    }

    private static ProductionAudioEntry WriteAndInspect(
        string path,
        string token,
        float[] samples,
        bool isMusic,
        int seed
    )
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path));
        SfInfo writeInfo = new SfInfo();
        writeInfo.samplerate = SampleRate;
        writeInfo.channels = Channels;
        writeInfo.format = FormatOggVorbis;
        IntPtr output = sf_open(path, SfmWrite, ref writeInfo);
        if (output == IntPtr.Zero)
            throw new InvalidOperationException("libsndfile open failed: " + ErrorText(output));
        double quality = Quality;
        sf_command(output, SetCompressionLevel, ref quality, sizeof(double));
        long frames = samples.Length / Channels;
        long written = sf_writef_float(output, samples, frames);
        sf_close(output);
        if (written != frames)
            throw new InvalidOperationException("libsndfile truncated " + token);

        SfInfo readInfo = new SfInfo();
        IntPtr input = sf_open(path, SfmRead, ref readInfo);
        if (input == IntPtr.Zero)
            throw new InvalidOperationException("libsndfile read-back failed: " + ErrorText(input));
        float[] decoded = new float[checked((int)(readInfo.frames * readInfo.channels))];
        long decodedFrames = sf_readf_float(input, decoded, readInfo.frames);
        sf_close(input);
        if (decodedFrames != readInfo.frames)
            throw new InvalidOperationException("libsndfile read-back truncated " + token);

        double peak = 0.0;
        for (int sample = 0; sample < decoded.Length; sample++)
            peak = Math.Max(peak, Math.Abs(decoded[sample]));
        double seamDbfs = -240.0;
        if (isMusic)
        {
            int seamFrames = (int)Math.Round(readInfo.samplerate * 0.05);
            double sum = 0.0;
            long count = (long)seamFrames * readInfo.channels;
            for (int frame = 0; frame < seamFrames; frame++)
            {
                for (int channel = 0; channel < readInfo.channels; channel++)
                {
                    double difference = decoded[frame * readInfo.channels + channel]
                        - decoded[(readInfo.frames - seamFrames + frame) * readInfo.channels + channel];
                    sum += difference * difference;
                }
            }
            seamDbfs = Dbfs(Math.Sqrt(sum / count));
        }

        ProductionAudioEntry entry = new ProductionAudioEntry();
        entry.Token = token;
        entry.Path = path;
        entry.Sha256 = Hash(path);
        entry.SampleRate = readInfo.samplerate;
        entry.Channels = readInfo.channels;
        entry.Frames = readInfo.frames;
        entry.DurationSeconds = Math.Round((double)readInfo.frames / readInfo.samplerate, 6);
        entry.TruePeakDbfs = Math.Round(Dbfs(peak), 4);
        entry.LoopSeamRmsDbfs = Math.Round(seamDbfs, 4);
        entry.LocalProcessingSeed = seed;
        entry.IsMusic = isMusic;
        return entry;
    }

    private static string ErrorText(IntPtr file)
    {
        IntPtr pointer = sf_strerror(file);
        return pointer == IntPtr.Zero ? "unknown error" : Marshal.PtrToStringAnsi(pointer);
    }

    private static double Dbfs(double value)
    {
        return 20.0 * Math.Log10(Math.Max(value, 1.0e-12));
    }

    private static string Hash(string path)
    {
        using (SHA256 sha = SHA256.Create())
        using (FileStream stream = File.OpenRead(path))
        {
            byte[] digest = sha.ComputeHash(stream);
            return BitConverter.ToString(digest).Replace("-", "").ToLowerInvariant();
        }
    }
}
