import 'dart:typed_data';

class SHA256 {

  // constants
  static const int BITS_PER_BYTE = 8; // no surprises here
  static const int WORD_SIZE = 4; // 4 bytes in a word
  static const int BITS_PER_WORD = WORD_SIZE * BITS_PER_BYTE;
  static const int WORDS_PER_BLOCK = 16; // for sha-256 a block is 512 bits
  static const int BYTES_PER_BLOCK = WORD_SIZE * WORDS_PER_BLOCK;
  static const int WORDS_PER_SCHEDULE = 64; // as defined in the spec
  static const int MIXING_STEPS = 64; // as defined in the spec
  static const int BYTE_MASK = 0xff; // byte mask
  static const int WORD_MASK = 0xffffffff; // used for addition mod 2^32
  static const List<int> K = const [ // comes from the spec
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b,
    0x59f111f1, 0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01,
    0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7,
    0xc19bf174, 0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc,
    0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da, 0x983e5152,
    0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
    0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc,
    0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819,
    0xd6990624, 0xf40e3585, 0x106aa070, 0x19a4c116, 0x1e376c08,
    0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f,
    0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
    0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2
  ];

  // helpers as defined in the spec
  // (sh)ift (r)ight
  static int shr(int f, int n) => f >> n;
  // (rot)ate (r)ight
  static int rotr(int f, int n) => (f >> n) | (f << (BITS_PER_WORD - n));
  static int parity(int x, int y, int z) => x ^ y ^ z;
  static int ch(x, y, z) => (x & y) ^ (~x & z);
  static int maj(x, y, z) => (x & y) ^ (x & z) ^ (y & z);
  // (b)ig (sig)ma 0
  static int bsig0(int x) => rotr(x, 2) ^ rotr(x, 13) ^ rotr(x, 22);
  // (b)ig (sig)ma 1
  static int bsig1(int x) => rotr(x, 6) ^ rotr(x, 11) ^ rotr(x, 25);
  // (s)mall (sig)ma 0
  static int ssig0(int x) => rotr(x, 7) ^ rotr(x, 18) ^ shr(x, 3);
  // (s)mall (sig)ma 1
  static int ssig1(int x) => rotr(x, 17) ^ rotr(x, 19) ^ shr(x, 10);
  static int add(int x, int y) => (x + y) & WORD_MASK;

  // generates hex digest given the output from the final round
  static String hexify(Uint32List l) {
    final StringBuffer hexString = new StringBuffer();
    for (final int uint in l) {
      for (final int hex in [
        (uint >> 24) & BYTE_MASK,
        (uint >> 16) & BYTE_MASK,
        (uint >> 8) & BYTE_MASK,
        (uint >> 0) & BYTE_MASK,
      ]) {
        hexString.write('${hex < 16 ? '0' : ''}${hex.toRadixString(16)}');
      }
    }
    return hexString.toString();
  }

  // we work with words (32 bits) so gotta convert bytes (8 bits) to words
  // and pad the result with what is defined in the spec
  static Iterable<int> words(Uint8List bytes) sync* {
    final int zeroPadding =
        (BYTES_PER_BLOCK - (bytes.lengthInBytes % BYTES_PER_BLOCK)) - 9;
    final int lengthInBits = bytes.lengthInBytes * BITS_PER_BYTE;
    // first we grab everything we know we can safely grab
    final int safeStrides = (bytes.lengthInBytes / WORD_SIZE).floor();
    final ByteData accumulator = new ByteData.view(new Uint8List(WORD_SIZE).buffer);
    int stride = 0;
    for (; stride < safeStrides; stride++) {
      for (int j = 0; j < WORD_SIZE; j++) {
        accumulator.setUint8(j, bytes[stride * WORD_SIZE + j]);
      }
      yield accumulator.getUint32(0);
    }
    // next we grab everything that is left over + 1 + zero padding
    final Iterable<int> leftOvers = bytes.getRange(stride * WORD_SIZE, bytes.lengthInBytes);
    final ByteData leftOverAccumulator = new ByteData.view(
        new Uint8List(leftOvers.length + 1 + zeroPadding).buffer);
    int i = 0;
    for (; i < leftOvers.length; i++) {
      leftOverAccumulator.setUint8(i, leftOvers.elementAt(i));
    }
    leftOverAccumulator.setUint8(i, 1 << (BITS_PER_BYTE - 1));
    final int leftOverLimit = (leftOverAccumulator.lengthInBytes / WORD_SIZE).floor();
    for (stride = 0; stride < leftOverLimit; stride++) {
      yield leftOverAccumulator.getUint32(stride * WORD_SIZE);
    }
    // finally the length
    final ByteData tail = new ByteData.view(new Uint8List(WORD_SIZE * 2).buffer);
    tail.setUint64(0, lengthInBits);
    yield tail.getUint32(0);
    yield tail.getUint32(WORD_SIZE);
  }

  // after we group bytes into words we have to group further
  // into 512 bits (16 words)
  static Iterable<Uint32List> blocks(Uint32List words) sync* {
    final Uint32List accumulator = new Uint32List(WORDS_PER_BLOCK);
    int i = 0;
    while (i < words.length) {
      for (int j = 0; j < WORDS_PER_BLOCK; j++) {
        accumulator[j] = words[i++];
      }
      yield accumulator;
    }
  }

  // expands each block into the words for the message schedule (16 words -> 64 words)
  // i think this is what is known as the expansion step of a hashing algorithm
  static Iterable<Uint32List> messageSchedule(Iterable<Uint32List> blocks) sync* {
    final Uint32List w = new Uint32List(WORDS_PER_SCHEDULE);
    for (final Uint32List block in blocks) {
      assert(block.length == WORDS_PER_BLOCK);
      int i = 0;
      for (final int word in block) {
        w[i++] = word;
      }
      for (; i < WORDS_PER_SCHEDULE; i++) {
        w[i] = ssig1(w[i - 2]) + w[i - 7] + ssig0(w[i - 15]) + w[i - 16];
      }
      yield w;
    }
  }

  // set the IV, grab the message schedule and start the mixing process to get
  // the final digest
  static Uint32List sha256(Uint8List bytes) {
    final List<int> wordList = words(bytes).toList(growable: false);
    final Uint32List w = new Uint32List.fromList(wordList);
    final Iterable<Uint32List> messageBlocks = blocks(w);
    final Uint32List H = new Uint32List.fromList([ // IV as defined in the spec
      0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f,
      0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    ]);
    int a = H[0]; int b = H[1];
    int c = H[2]; int d = H[3];
    int e = H[4]; int f = H[5];
    int g = H[6]; int h = H[7];
    for (final Uint32List schedule in messageSchedule(messageBlocks)) {
      int t = 0;
      for (; t < MIXING_STEPS; t++) { // mix it up!
        final int t1 = h + bsig1(e) + ch(e, f, g) + K[t] + schedule[t];
        final int t2 = bsig0(a) + maj(a, b, c);
        h = g; g = f; f = e;
        e = add(d, t1);
        d = c; c = b; b = a;
        a = add(t1, t2);
      }
      H[0] = add(a, H[0]); H[1] = add(b, H[1]);
      H[2] = add(c, H[2]); H[3] = add(d, H[3]);
      H[4] = add(e, H[4]); H[5] = add(f, H[5]);
      H[6] = add(g, H[6]); H[7] = add(h, H[7]);
    }
    return H;
  }

}

main() async {
  final codeUnits = ''.codeUnits;
  final Uint8List content = new Uint8List.fromList(codeUnits);
  final Uint32List hash = SHA256.sha256(content);
  final hexString = SHA256.hexify(hash);
  print(hexString);
  assert(hexString == 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
}
