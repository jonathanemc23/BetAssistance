import 'slip_reader.dart';

/// Phones read slips with ML Kit; this only exists so the app compiles.
class TesseractSlipScanner implements SlipScanner {
  @override
  Future<List<SlipLine>> scan(String imagePath) => throw UnsupportedError('Tesseract.js only runs in the browser');
}
