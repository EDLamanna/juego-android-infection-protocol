import 'dart:math';

class SeededRandom {
  SeededRandom(int seed) : _random = Random(seed);

  final Random _random;

  int nextInt(int max) => _random.nextInt(max);

  List<T> shuffled<T>(List<T> input) {
    final copy = List<T>.from(input);
    for (var i = copy.length - 1; i > 0; i--) {
      final j = _random.nextInt(i + 1);
      final temp = copy[i];
      copy[i] = copy[j];
      copy[j] = temp;
    }
    return copy;
  }
}
