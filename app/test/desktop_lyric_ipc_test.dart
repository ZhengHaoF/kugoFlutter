import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kugo/features/desktop_lyric/desktop_lyric_ipc.dart';

void main() {
  group('LyricIpc codec', () {
    test(
      'Linux hello requires a nonempty matching token and correct envelope',
      () {
        expect(
          LyricIpc.isAuthenticatedHello(
            LyricIpc.cmd('hello', {'token': 'secret'}),
            'secret',
          ),
          isTrue,
        );
        expect(
          LyricIpc.isAuthenticatedHello(
            LyricIpc.cmd('hello', {'token': 'wrong'}),
            'secret',
          ),
          isFalse,
        );
        expect(
          LyricIpc.isAuthenticatedHello(
            LyricIpc.cmd('hello', {'token': ''}),
            '',
          ),
          isFalse,
        );
        expect(
          LyricIpc.isAuthenticatedHello(
            LyricIpc.cmd('ready', {'token': 'secret'}),
            'secret',
          ),
          isFalse,
        );
      },
    );
    test('encode/decode roundtrip keeps type and payload', () {
      final line = LyricIpc.encodeLine(LyricIpc.snapshot({'a': 1}));
      final msg = LyricIpc.decodeLine(line)!;
      expect(msg['t'], LyricIpc.typeSnapshot);
      expect((msg['d'] as Map)['a'], 1);
    });

    test('cmd messages carry method and optional data', () {
      final withData = LyricIpc.decodeLine(
        LyricIpc.encodeLine(LyricIpc.cmd('bounds', {'x': 1.5})),
      )!;
      expect(withData['t'], LyricIpc.typeCmd);
      expect(withData['m'], 'bounds');
      expect((withData['d'] as Map)['x'], 1.5);

      final bare = LyricIpc.decodeLine(
        LyricIpc.encodeLine(LyricIpc.cmd('ready')),
      )!;
      expect(bare['m'], 'ready');
      expect(bare.containsKey('d'), isFalse);
    });

    test('garbage lines decode to null instead of throwing', () {
      expect(LyricIpc.decodeLine(''), isNull);
      expect(LyricIpc.decodeLine('   '), isNull);
      expect(LyricIpc.decodeLine('{not json'), isNull);
    });

    test('portFromArgs reads --ipc-port=', () {
      expect(
        LyricIpc.portFromArgs(['desktop_lyric', '--ipc-port=12345']),
        12345,
      );
      expect(LyricIpc.portFromArgs(['desktop_lyric']), isNull);
    });

    test('isLyricProcessArgs detects the process flag', () {
      expect(LyricIpc.isLyricProcessArgs(['desktop_lyric']), isTrue);
      expect(LyricIpc.isLyricProcessArgs(['other']), isFalse);
    });
  });

  group('LyricIpc socket framing', () {
    test(
      'writer closes promptly after the shared reader destroys its socket',
      () async {
        final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
        final accepted = server.first;
        final client = await Socket.connect('127.0.0.1', server.port);
        final peer = await accepted;
        final reader = LyricIpcReader(client);
        final writer = LyricIpcWriter(client);
        try {
          await reader.close().timeout(const Duration(seconds: 2));
          await writer.close().timeout(const Duration(seconds: 2));
        } finally {
          client.destroy();
          peer.destroy();
          await server.close();
        }
      },
    );
    test('reader splits newline-delimited frames', () async {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final got = <Map<String, Object?>>[];
      final done = Completer<void>();

      server.listen((socket) {
        final reader = LyricIpcReader(socket);
        reader.messages.listen((m) {
          got.add(m);
          if (got.length == 2 && !done.isCompleted) done.complete();
        });
      });

      final client = await Socket.connect(
        InternetAddress.loopbackIPv4,
        server.port,
      );
      final a = LyricIpc.encodeLine(LyricIpc.cmd('ready'));
      final b = LyricIpc.encodeLine(LyricIpc.signal(LyricIpc.typeShow));
      // 故意拆包：半行 + 后半行 + 完整行，验证缓冲重组。
      client.write(a.substring(0, 5));
      await client.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      client.write('${a.substring(5)}\n$b\n');
      await client.flush();

      await done.future.timeout(const Duration(seconds: 2));
      expect(got[0]['m'], 'ready');
      expect(got[1]['t'], LyricIpc.typeShow);

      client.destroy();
      await server.close();
    });

    test('connectLyricIpc retries then succeeds', () async {
      // 先占端口再释放，模拟「进程刚起来端口尚未 accept」的短窗。
      final probe = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = probe.port;
      unawaited(probe.close());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final server = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        port,
      );
      final socketFut = connectLyricIpc(port, retries: 30);
      final accepted = await server.first;
      final socket = await socketFut;
      expect(socket.remotePort, port);
      socket.destroy();
      accepted.destroy();
      await server.close();
    });
  });
}
