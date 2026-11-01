import 'slip_reader.dart';
import 'web_slip_scanner_stub.dart' if (dart.library.js_interop) 'web_slip_scanner_web.dart' as impl;

/// Reads slip screenshots in the web app (Safari on iPhone), where ML Kit
/// isn't available: Tesseract.js in the browser, loaded the first time it's
/// used. The picture stays on the device.
SlipScanner webSlipScanner() => impl.TesseractSlipScanner();
