using System.Buffers.Binary;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace CodexRadar.Windows;

internal sealed class ManagedAppServerTransportException(string message)
    : IOException(message);

internal sealed class ManagedAppServerHandshake
{
    private const int MaximumHeaderBytes = 64 * 1024;
    private const string WebSocketGuid = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11";
    private static readonly byte[] HeaderTerminator = "\r\n\r\n"u8.ToArray();

    public ManagedAppServerHandshake(string? key = null)
    {
        Key = key ?? Convert.ToBase64String(RandomNumberGenerator.GetBytes(16));
        ExpectedAccept = AcceptValue(Key);
    }

    public string Key { get; }
    public string ExpectedAccept { get; }

    public byte[] Request => Encoding.ASCII.GetBytes(string.Join("\r\n",
    [
        "GET / HTTP/1.1",
        "Host: localhost",
        "Connection: Upgrade",
        "Upgrade: websocket",
        $"Sec-WebSocket-Key: {Key}",
        "Sec-WebSocket-Version: 13",
        "",
        ""
    ]));

    public bool TryConsumeResponse(List<byte> buffer)
    {
        var terminator = IndexOf(buffer, HeaderTerminator);
        if (terminator < 0)
        {
            if (buffer.Count > MaximumHeaderBytes)
                throw new ManagedAppServerTransportException(
                    "The managed Codex app-server handshake was too large.");
            return false;
        }

        var headerLength = terminator + HeaderTerminator.Length;
        if (headerLength > MaximumHeaderBytes)
            throw new ManagedAppServerTransportException(
                "The managed Codex app-server handshake was too large.");
        string header;
        try
        {
            header = new UTF8Encoding(false, true).GetString(
                buffer.GetRange(0, headerLength).ToArray());
        }
        catch (DecoderFallbackException ex)
        {
            throw new ManagedAppServerTransportException(
                $"The managed Codex app-server handshake was invalid: {ex.Message}");
        }
        buffer.RemoveRange(0, headerLength);

        var lines = header.Split("\r\n", StringSplitOptions.None);
        if (lines.Length == 0
            || !lines[0].StartsWith("HTTP/1.1 101 ", StringComparison.Ordinal))
            throw new ManagedAppServerTransportException(
                "The managed Codex app-server handshake was rejected.");

        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var line in lines.Skip(1).Where(line => line.Length > 0))
        {
            var separator = line.IndexOf(':');
            if (separator <= 0)
                throw new ManagedAppServerTransportException(
                    "The managed Codex app-server handshake contained an invalid header.");
            var name = line[..separator].Trim();
            var value = line[(separator + 1)..].Trim();
            headers[name] = headers.TryGetValue(name, out var previous)
                ? $"{previous},{value}"
                : value;
        }

        var connectionTokens = headers.TryGetValue("Connection", out var connection)
            ? connection.Split(',').Select(token => token.Trim())
            : [];
        if (!headers.TryGetValue("Upgrade", out var upgrade)
            || !upgrade.Equals("websocket", StringComparison.OrdinalIgnoreCase)
            || !connectionTokens.Contains("upgrade", StringComparer.OrdinalIgnoreCase)
            || !headers.TryGetValue("Sec-WebSocket-Accept", out var accept)
            || !CryptographicOperations.FixedTimeEquals(
                Encoding.ASCII.GetBytes(accept),
                Encoding.ASCII.GetBytes(ExpectedAccept)))
            throw new ManagedAppServerTransportException(
                "The managed Codex app-server handshake proof was invalid.");
        return true;
    }

    internal static string AcceptValue(string key) => Convert.ToBase64String(
        SHA1.HashData(Encoding.ASCII.GetBytes(key + WebSocketGuid)));

    private static int IndexOf(IReadOnlyList<byte> buffer, IReadOnlyList<byte> value)
    {
        if (value.Count == 0) return 0;
        for (var index = 0; index <= buffer.Count - value.Count; index++)
        {
            var matches = true;
            for (var offset = 0; offset < value.Count; offset++)
                if (buffer[index + offset] != value[offset])
                {
                    matches = false;
                    break;
                }
            if (matches) return index;
        }
        return -1;
    }
}

internal enum ManagedWebSocketEventKind
{
    Text,
    Ping,
    Close
}

internal sealed record ManagedWebSocketEvent(
    ManagedWebSocketEventKind Kind,
    byte[] Payload);

internal sealed class ManagedAppServerWebSocketCodec
{
    private const int MaximumMessageBytes = 8 * 1024 * 1024;
    private readonly List<byte> _buffer = [];
    private readonly List<byte> _fragmentedText = [];
    private bool _receivesContinuation;

    public IReadOnlyList<ManagedWebSocketEvent> Append(ReadOnlySpan<byte> bytes)
    {
        foreach (var value in bytes) _buffer.Add(value);
        var events = new List<ManagedWebSocketEvent>();
        while (TryReadFrame(out var frame))
        {
            switch (frame.Opcode)
            {
                case 0x0:
                    if (!_receivesContinuation)
                        throw InvalidFrame();
                    AppendFragment(frame.Payload);
                    if (frame.IsFinal)
                    {
                        events.Add(new ManagedWebSocketEvent(
                            ManagedWebSocketEventKind.Text,
                            _fragmentedText.ToArray()));
                        _fragmentedText.Clear();
                        _receivesContinuation = false;
                    }
                    break;
                case 0x1:
                    if (_receivesContinuation)
                        throw InvalidFrame();
                    if (frame.IsFinal)
                    {
                        events.Add(new ManagedWebSocketEvent(
                            ManagedWebSocketEventKind.Text,
                            frame.Payload));
                    }
                    else
                    {
                        _receivesContinuation = true;
                        _fragmentedText.AddRange(frame.Payload);
                        ValidateMessageSize(_fragmentedText.Count);
                    }
                    break;
                case 0x8:
                    ValidateControlFrame(frame);
                    events.Add(new ManagedWebSocketEvent(
                        ManagedWebSocketEventKind.Close,
                        frame.Payload));
                    break;
                case 0x9:
                    ValidateControlFrame(frame);
                    events.Add(new ManagedWebSocketEvent(
                        ManagedWebSocketEventKind.Ping,
                        frame.Payload));
                    break;
                case 0xA:
                    ValidateControlFrame(frame);
                    break;
                default:
                    throw InvalidFrame();
            }
        }
        return events;
    }

    public static byte[] ClientFrame(
        byte[] payload,
        byte opcode = 0x1,
        byte[]? mask = null)
    {
        if (opcode > 0xF) throw new ArgumentOutOfRangeException(nameof(opcode));
        mask ??= RandomNumberGenerator.GetBytes(4);
        if (mask.Length != 4)
            throw new ArgumentException("A WebSocket mask must contain four bytes.", nameof(mask));

        var lengthBytes = payload.Length < 126 ? 0 : payload.Length <= ushort.MaxValue ? 2 : 8;
        var frame = new byte[2 + lengthBytes + 4 + payload.Length];
        frame[0] = (byte)(0x80 | opcode);
        var cursor = 2;
        if (payload.Length < 126)
            frame[1] = (byte)(0x80 | payload.Length);
        else if (payload.Length <= ushort.MaxValue)
        {
            frame[1] = 0x80 | 126;
            BinaryPrimitives.WriteUInt16BigEndian(
                frame.AsSpan(cursor, 2), (ushort)payload.Length);
            cursor += 2;
        }
        else
        {
            frame[1] = 0x80 | 127;
            BinaryPrimitives.WriteUInt64BigEndian(
                frame.AsSpan(cursor, 8), (ulong)payload.Length);
            cursor += 8;
        }
        mask.CopyTo(frame, cursor);
        cursor += mask.Length;
        for (var index = 0; index < payload.Length; index++)
            frame[cursor + index] = (byte)(payload[index] ^ mask[index % 4]);
        return frame;
    }

    private bool TryReadFrame(out ManagedWebSocketFrame frame)
    {
        frame = default;
        if (_buffer.Count < 2) return false;
        var first = _buffer[0];
        var second = _buffer[1];
        if ((first & 0x70) != 0 || (second & 0x80) != 0)
            throw InvalidFrame();

        var cursor = 2;
        ulong length = (uint)(second & 0x7F);
        if (length == 126)
        {
            if (_buffer.Count < cursor + 2) return false;
            length = BinaryPrimitives.ReadUInt16BigEndian(
                new byte[] { _buffer[cursor], _buffer[cursor + 1] });
            cursor += 2;
        }
        else if (length == 127)
        {
            if (_buffer.Count < cursor + 8) return false;
            if ((_buffer[cursor] & 0x80) != 0) throw InvalidFrame();
            Span<byte> lengthBuffer = stackalloc byte[8];
            for (var index = 0; index < 8; index++)
                lengthBuffer[index] = _buffer[cursor + index];
            length = BinaryPrimitives.ReadUInt64BigEndian(lengthBuffer);
            cursor += 8;
        }
        if (length > MaximumMessageBytes || length > int.MaxValue)
            throw new ManagedAppServerTransportException(
                "The managed Codex app-server message was too large.");
        var payloadLength = (int)length;
        if (_buffer.Count < cursor + payloadLength) return false;
        var payload = _buffer.GetRange(cursor, payloadLength).ToArray();
        _buffer.RemoveRange(0, cursor + payloadLength);
        frame = new ManagedWebSocketFrame(
            (first & 0x80) != 0,
            (byte)(first & 0x0F),
            payload);
        return true;
    }

    private void AppendFragment(byte[] payload)
    {
        ValidateMessageSize(_fragmentedText.Count + payload.Length);
        _fragmentedText.AddRange(payload);
    }

    private static void ValidateMessageSize(int size)
    {
        if (size > MaximumMessageBytes)
            throw new ManagedAppServerTransportException(
                "The managed Codex app-server message was too large.");
    }

    private static void ValidateControlFrame(ManagedWebSocketFrame frame)
    {
        if (!frame.IsFinal || frame.Payload.Length > 125)
            throw InvalidFrame();
    }

    private static ManagedAppServerTransportException InvalidFrame() =>
        new("The managed Codex app-server sent an invalid WebSocket frame.");

    private readonly record struct ManagedWebSocketFrame(
        bool IsFinal,
        byte Opcode,
        byte[] Payload);
}

internal sealed class ManagedAppServerConnection : IDisposable
{
    private readonly Stream _input;
    private readonly Stream _output;
    private readonly ManagedAppServerWebSocketCodec _codec = new();
    private readonly Queue<ManagedWebSocketEvent> _events = new();
    private readonly byte[] _readBuffer = new byte[16 * 1024];
    private bool _disposed;

    private ManagedAppServerConnection(Stream input, Stream output)
    {
        _input = input;
        _output = output;
    }

    public static async Task<ManagedAppServerConnection> ConnectAsync(
        Stream input,
        Stream output,
        CancellationToken cancellationToken)
    {
        var connection = new ManagedAppServerConnection(input, output);
        try
        {
            await connection.PerformHandshakeAsync(cancellationToken)
                .ConfigureAwait(false);
            return connection;
        }
        catch
        {
            connection.Dispose();
            throw;
        }
    }

    public async Task<JsonDocument> RequestAsync(
        int id,
        byte[] payload,
        CancellationToken cancellationToken,
        Action<Action>? authorizedDispatch = null)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var frame = ManagedAppServerWebSocketCodec.ClientFrame(payload);
        await WriteFrameAsync(frame, cancellationToken, authorizedDispatch)
            .ConfigureAwait(false);
        return await ReadResponseAsync(id, cancellationToken)
            .ConfigureAwait(false);
    }

    public async Task SendNotificationAsync(
        byte[] payload,
        CancellationToken cancellationToken)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        await WriteFrameAsync(
                ManagedAppServerWebSocketCodec.ClientFrame(payload),
                cancellationToken,
                null)
            .ConfigureAwait(false);
    }

    private async Task PerformHandshakeAsync(CancellationToken cancellationToken)
    {
        var handshake = new ManagedAppServerHandshake();
        await _input.WriteAsync(handshake.Request, cancellationToken)
            .ConfigureAwait(false);
        await _input.FlushAsync(cancellationToken).ConfigureAwait(false);

        var buffer = new List<byte>();
        while (!handshake.TryConsumeResponse(buffer))
        {
            var count = await _output.ReadAsync(_readBuffer, cancellationToken)
                .ConfigureAwait(false);
            if (count == 0)
                throw new EndOfStreamException(
                    "The managed Codex app-server ended during its handshake.");
            buffer.AddRange(_readBuffer.AsSpan(0, count).ToArray());
        }
        if (buffer.Count > 0)
            Enqueue(_codec.Append(buffer.ToArray()));
    }

    private async Task<JsonDocument> ReadResponseAsync(
        int expectedId,
        CancellationToken cancellationToken)
    {
        while (true)
        {
            while (_events.TryDequeue(out var websocketEvent))
            {
                switch (websocketEvent.Kind)
                {
                    case ManagedWebSocketEventKind.Ping:
                        await WriteFrameAsync(
                                ManagedAppServerWebSocketCodec.ClientFrame(
                                    websocketEvent.Payload,
                                    0xA),
                                cancellationToken,
                                null)
                            .ConfigureAwait(false);
                        continue;
                    case ManagedWebSocketEventKind.Close:
                        throw new EndOfStreamException(
                            "The managed Codex app-server closed its connection.");
                    case ManagedWebSocketEventKind.Text:
                        JsonDocument document;
                        try
                        {
                            document = JsonDocument.Parse(websocketEvent.Payload);
                        }
                        catch (JsonException ex)
                        {
                            throw new ManagedAppServerTransportException(
                                $"The managed Codex app-server sent invalid JSON: {ex.Message}");
                        }
                        if (document.RootElement.Int32("id") == expectedId)
                            return document;
                        document.Dispose();
                        continue;
                }
            }

            var count = await _output.ReadAsync(_readBuffer, cancellationToken)
                .ConfigureAwait(false);
            if (count == 0)
                throw new EndOfStreamException(
                    "The managed Codex app-server ended before replying.");
            Enqueue(_codec.Append(_readBuffer.AsSpan(0, count)));
        }
    }

    private async Task WriteFrameAsync(
        byte[] frame,
        CancellationToken cancellationToken,
        Action<Action>? authorizedDispatch)
    {
        if (authorizedDispatch is null)
        {
            await _input.WriteAsync(frame, cancellationToken).ConfigureAwait(false);
            await _input.FlushAsync(cancellationToken).ConfigureAwait(false);
            return;
        }
        authorizedDispatch(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            _input.Write(frame);
            _input.Flush();
        });
    }

    private void Enqueue(IEnumerable<ManagedWebSocketEvent> events)
    {
        foreach (var websocketEvent in events) _events.Enqueue(websocketEvent);
    }

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        try { _input.Dispose(); } catch { }
        try { _output.Dispose(); } catch { }
    }
}

internal static class CodexManagedAppServerLocator
{
    internal static string? FindControlSocket() => FindControlSocket(
        Environment.GetEnvironmentVariable("CODEX_HOME"),
        Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));

    internal static string? FindControlSocket(
        string? codexHomeOverride,
        string userProfile)
    {
        try
        {
            var codexHome = !string.IsNullOrWhiteSpace(codexHomeOverride)
                            && Path.IsPathRooted(codexHomeOverride)
                ? Path.GetFullPath(codexHomeOverride)
                : Path.Combine(Path.GetFullPath(userProfile), ".codex");
            if (AppServerClient.IsNetworkPath(codexHome)) return null;
            var socket = Path.GetFullPath(Path.Combine(
                codexHome,
                "app-server-control",
                "app-server-control.sock"));
            var controlDirectory = Path.GetDirectoryName(socket)
                                   ?? throw new InvalidDataException(
                                       "The managed control socket has no parent directory.");
            var expectedRoot = Path.GetFullPath(codexHome)
                .TrimEnd(Path.DirectorySeparatorChar)
                + Path.DirectorySeparatorChar;
            if (!socket.StartsWith(expectedRoot, StringComparison.OrdinalIgnoreCase)
                || !Directory.Exists(controlDirectory)
                || !PrivateStorageSecurity.IsRestrictedToCurrentUser(
                    controlDirectory)
                || !PrivateStorageSecurity.IsUnixDomainSocket(socket))
                return null;
            return socket;
        }
        catch
        {
            return null;
        }
    }
}
