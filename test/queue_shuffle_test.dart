import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:lumina_player/services/audio_handler.dart';

void _expectValidPermutation(List<int> indices, int expectedLength) {
  expect(indices.length, expectedLength);
  final sorted = List<int>.of(indices)..sort();
  expect(sorted, List<int>.generate(expectedLength, (i) => i));
}

void main() {
  group('QueueAwareShuffleOrder', () {
    test('inserts user-queued songs in FIFO order right after current in shuffle', () {
      final order = QueueAwareShuffleOrder(random: Random(42));
      order.insert(0, 6);
      order.shuffle(initialIndex: 2);

      _expectValidPermutation(order.indices, 6);
      expect(order.indices.first, 2);

      // Encolar canción Q1 (raw index 3) justo después de current (pos 0 -> pos 1)
      order.pendingInsertShufflePos = 1;
      order.insert(3, 1);
      order.pendingInsertShufflePos = null;

      _expectValidPermutation(order.indices, 7);
      expect(order.indices[0], 2);
      expect(order.indices[1], 3);

      // Encolar canción Q2 (raw index 4) en FIFO justo después de Q1 (pos 2)
      order.pendingInsertShufflePos = 2;
      order.insert(4, 1);
      order.pendingInsertShufflePos = null;

      _expectValidPermutation(order.indices, 8);
      expect(order.indices[0], 2);
      expect(order.indices[1], 3);
      expect(order.indices[2], 4);
    });

    test('moving a song up to 1st or 2nd in shuffle never loses or hides it', () {
      final order = QueueAwareShuffleOrder(random: Random(7));
      order.insert(0, 8);
      order.shuffle(initialIndex: 3);

      final before = List<int>.of(order.indices);
      final currentSong = before[0];
      final lastSong = before[7];
      final fifthSong = before[5];

      // Mover la última canción al puesto #1 (justo después de la actual)
      expect(order.moveEffectiveIndex(7, 1), isTrue);
      _expectValidPermutation(order.indices, 8);
      expect(order.indices[0], currentSong);
      expect(order.indices[1], lastSong);
      expect(order.indices.contains(lastSong), isTrue);

      // Mover otra canción al puesto #2
      final fifthCurrentPos = order.indices.indexOf(fifthSong);
      expect(fifthCurrentPos, greaterThan(2));
      expect(order.moveEffectiveIndex(fifthCurrentPos, 2), isTrue);
      _expectValidPermutation(order.indices, 8);
      expect(order.indices[0], currentSong);
      expect(order.indices[1], lastSong);
      expect(order.indices[2], fifthSong);
    });

    test('suppressNextShuffle preserves manual reorder during player sync', () {
      final order = QueueAwareShuffleOrder(random: Random(99));
      order.insert(0, 6);
      order.shuffle(initialIndex: 1);

      order.moveEffectiveIndex(5, 1);
      final expected = List<int>.of(order.indices);

      order.suppressNextShuffle = true;
      order.shuffle(initialIndex: 1);
      order.suppressNextShuffle = false;

      expect(order.indices, expected);
    });

    test('shuffle preserves current song and queued songs in FIFO order', () {
      var preserved = <int>[4, 5];
      final order = QueueAwareShuffleOrder(
        random: Random(123),
        getPreservedUpcomingIndices: () => preserved,
      );
      order.insert(0, 10);

      order.shuffle(initialIndex: 3);

      _expectValidPermutation(order.indices, 10);
      expect(order.indices[0], 3);
      expect(order.indices[1], 4);
      expect(order.indices[2], 5);

      // Volver a mezclar sin canciones encoladas cambia el resto pero mantiene actual
      preserved = <int>[];
      order.forcedInitialIndex = 7;
      order.shuffle(initialIndex: 0);
      order.forcedInitialIndex = null;

      _expectValidPermutation(order.indices, 10);
      expect(order.indices[0], 7);
    });

    test('inserting after reordering in shuffle keeps reordered items intact', () {
      final order = QueueAwareShuffleOrder(random: Random(11));
      order.insert(0, 6);
      order.shuffle(initialIndex: 0);

      final songMovedToFirst = order.indices[5];
      order.moveEffectiveIndex(5, 1);
      expect(order.indices[1], songMovedToFirst);

      // Ahora insertamos una nueva canción al final de la cola (raw index 1)
      // en la posición shuffle 2 (justo después de la movida si fue promovida)
      order.pendingInsertShufflePos = 2;
      order.insert(1, 1);
      order.pendingInsertShufflePos = null;

      _expectValidPermutation(order.indices, 7);
      expect(order.indices[0], 0);
      // songMovedToFirst era >= 1, así que su índice real se desplazó +1
      expect(order.indices[1], songMovedToFirst + 1);
      expect(order.indices[2], 1);
    });

    test('removeRange shifts higher indices without breaking shuffle order', () {
      final order = QueueAwareShuffleOrder(random: Random(5));
      order.insert(0, 5);
      order.indices
        ..clear()
        ..addAll([3, 0, 4, 1, 2]);

      // Eliminar índice real 0 (que está en pos 1, menor que actual 3)
      order.removeRange(0, 1);

      _expectValidPermutation(order.indices, 4);
      // 3->2, 4->3, 1->0, 2->1
      expect(order.indices, [2, 3, 0, 1]);
    });

    test('stress test: repeated inserts, moves, removes, and shuffles preserve bijection', () {
      final rng = Random(2026);
      final order = QueueAwareShuffleOrder(random: rng);
      order.insert(0, 15);
      order.shuffle(initialIndex: 4);

      for (var step = 0; step < 50; step++) {
        final n = order.indices.length;
        final op = step % 4;
        if (op == 0) {
          // Insertar en posición shuffle controlada después de pos 0
          final rawIdx = rng.nextInt(n + 1);
          order.pendingInsertShufflePos = 1 + rng.nextInt(n);
          order.insert(rawIdx, 1);
          order.pendingInsertShufflePos = null;
          _expectValidPermutation(order.indices, n + 1);
        } else if (op == 1 && n > 2) {
          // Reordenar dentro de las próximas (posiciones 1..n-1)
          final from = 1 + rng.nextInt(n - 1);
          final to = 1 + rng.nextInt(n - 1);
          final movedVal = order.indices[from];
          order.moveEffectiveIndex(from, to);
          expect(order.indices[to], movedVal);
          _expectValidPermutation(order.indices, n);
        } else if (op == 2 && n > 3) {
          // Eliminar una canción que no sea la actual (pos 0)
          final removePos = 1 + rng.nextInt(n - 1);
          final actualToRemove = order.indices[removePos];
          order.removeRange(actualToRemove, actualToRemove + 1);
          _expectValidPermutation(order.indices, n - 1);
        } else {
          // Re-barajar manteniendo pos 0
          final currentActual = order.indices.first;
          order.shuffle(initialIndex: currentActual);
          expect(order.indices.first, currentActual);
          _expectValidPermutation(order.indices, n);
        }
      }
    });
  });
}
