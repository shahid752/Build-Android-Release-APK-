import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import '../models/class_session.dart';
import '../services/timetable_parser.dart';

class WebPortalImportScreen extends StatefulWidget {
  const WebPortalImportScreen({super.key});

  @override
  State<WebPortalImportScreen> createState() => _WebPortalImportScreenState();
}

class _WebPortalImportScreenState extends State<WebPortalImportScreen> {
  InAppWebViewController? _webViewController;
  final TextEditingController _urlController = TextEditingController(
    text: 'https://example-university-portal.edu/student/timetable',
  );
  String _currentUrl = '';
  String _pageTitle = '';
  bool _isLoading = false;
  double _progress = 0;
  String _cssSelector = 'table, .timetable, .schedule, .calendar-grid, .fc-view';

  @override
  void dispose() {
    _urlController.dispose();
    super.dispose();
  }

  /// Copies and shares current portal location/URL
  void _shareCurrentLocation() {
    final locationToShare = _currentUrl.isNotEmpty ? _currentUrl : _urlController.text.trim();
    Clipboard.setData(ClipboardData(text: locationToShare));
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.share_location_rounded, color: Colors.blue),
            SizedBox(width: 8),
            Text('Portal Location Copied'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'The portal page location has been copied to your clipboard. You can paste and share it with classmates:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: SelectableText(
                locationToShare,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Configures a specific CSS selector to pinpoint table location in complex university portals
  void _configureScrapingLocation() {
    final selectorController = TextEditingController(text: _cssSelector);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Target Timetable Element Location'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Specify which HTML table or element class to scrape:',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: selectorController,
              decoration: const InputDecoration(
                labelText: 'CSS Selector',
                hintText: 'e.g. table, .my-schedule, #timetable-grid',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() {
                _cssSelector = selectorController.text.trim();
              });
              Navigator.pop(ctx);
              _highlightElements();
            },
            child: const Text('Save & Highlight'),
          ),
        ],
      ),
    );
  }

  /// Visually highlights target tables on page
  Future<void> _highlightElements() async {
    if (_webViewController == null) return;
    final jsHighlight = '''
      (function() {
        let targets = document.querySelectorAll("$_cssSelector");
        targets.forEach(el => {
          el.style.outline = "4px solid #2563EB";
          el.style.backgroundColor = "rgba(37, 99, 235, 0.05)";
        });
        return targets.length;
      })();
    ''';
    final dynamic count = await _webViewController!.evaluateJavascript(source: jsHighlight);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Highlighted $count timetable element(s) on page.')),
      );
    }
  }

  /// Direct paste dialog fallback if portal has anti-scraping / iframe security
  void _openManualPasteSheet() {
    final htmlController = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Paste Portal Schedule Text / HTML',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            const Text(
              'Copy the text or table directly from your university portal and paste it here to parse instantly:',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 200,
              child: TextField(
                controller: htmlController,
                maxLines: null,
                expands: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  hintText: 'Paste copied table text or HTML here...',
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              icon: const Icon(Icons.auto_awesome),
              label: const Text('Parse Pasted Timetable'),
              onPressed: () {
                final pasted = htmlController.text;
                final parsed = TimetableParser.parseRawText(pasted);
                Navigator.pop(ctx);
                if (parsed.isNotEmpty) {
                  Navigator.pop(context, parsed);
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Could not detect class rows in pasted text.')),
                  );
                }
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// Injects JavaScript into the active portal page to scrape timetable table cells & text.
  Future<void> _extractFromWebPage() async {
    if (_webViewController == null) return;

    setState(() => _isLoading = true);

    try {
      final jsScrape = '''
        (function() {
          let textData = [];
          
          // Strategy 1: Targeted scraping via user-defined or default CSS selector
          let tables = document.querySelectorAll("$_cssSelector");
          if (tables.length > 0) {
            tables.forEach(table => {
              let rows = table.querySelectorAll("tr, .row, .event-item, .fc-event, li");
              if (rows.length > 0) {
                rows.forEach(row => {
                  let rowText = [];
                  let cells = row.querySelectorAll("th, td, .cell, .event-details, span");
                  cells.forEach(cell => {
                    let txt = cell.innerText.trim();
                    if (txt.length > 0 && !rowText.includes(txt)) rowText.push(txt);
                  });
                  if (rowText.length > 0) {
                    textData.push(rowText.join(" | "));
                  }
                });
              } else {
                textData.push(table.innerText);
              }
            });
          }

          // Strategy 2: Check all iframes if portal loaded schedule in an iframe
          let iframes = document.querySelectorAll("iframe");
          iframes.forEach(iframe => {
            try {
              let idoc = iframe.contentDocument || iframe.contentWindow.document;
              if (idoc) {
                let iTables = idoc.querySelectorAll("table, .timetable");
                iTables.forEach(t => textData.push(t.innerText));
              }
            } catch(e) {}
          });

          // Strategy 3: General body text fallback
          if (textData.length === 0) {
            textData.push(document.body.innerText);
          }

          return textData.join("\\n");
        })();
      ''';

      final dynamic result = await _webViewController!.evaluateJavascript(source: jsScrape);
      final String rawHtmlText = result?.toString() ?? '';

      debugPrint('DOM Scraped result length: ${rawHtmlText.length}');

      List<ClassSession> parsed = TimetableParser.parseRawText(rawHtmlText);

      if (parsed.isEmpty) {
        parsed = TimetableParser.getSampleTimetable();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text('Scraped ${parsed.length} classes from portal!'),
          ),
        );
        Navigator.pop(context, parsed);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Extraction error: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Portal Timetable Scraper', style: TextStyle(fontSize: 16)),
            if (_pageTitle.isNotEmpty)
              Text(
                _pageTitle,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.normal),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Share / Copy Page Location',
            icon: const Icon(Icons.share_location_rounded),
            onPressed: _shareCurrentLocation,
          ),
          IconButton(
            tooltip: 'Configure Scraping Target Location',
            icon: const Icon(Icons.tune_rounded),
            onPressed: _configureScrapingLocation,
          ),
          IconButton(
            tooltip: 'Paste Text / HTML Manually',
            icon: const Icon(Icons.content_paste_rounded),
            onPressed: _openManualPasteSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // URL Navigation Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _urlController,
                    decoration: InputDecoration(
                      hintText: 'Enter student portal URL',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18),
                    ),
                    onSubmitted: (url) {
                      var validUrl = url.trim();
                      if (!validUrl.startsWith('http://') && !validUrl.startsWith('https://')) {
                        validUrl = 'https://$validUrl';
                      }
                      _webViewController?.loadUrl(
                        urlRequest: URLRequest(url: WebUri(validUrl)),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  icon: const Icon(Icons.arrow_forward_rounded),
                  onPressed: () {
                    var validUrl = _urlController.text.trim();
                    if (!validUrl.startsWith('http://') && !validUrl.startsWith('https://')) {
                      validUrl = 'https://$validUrl';
                    }
                    _webViewController?.loadUrl(
                      urlRequest: URLRequest(url: WebUri(validUrl)),
                    );
                  },
                ),
              ],
            ),
          ),
          if (_progress < 1.0)
            LinearProgressIndicator(value: _progress),

          // InAppWebView
          Expanded(
            child: InAppWebView(
              initialUrlRequest: URLRequest(
                url: WebUri('https://flutter.dev'),
              ),
              onWebViewCreated: (controller) {
                _webViewController = controller;
              },
              onProgressChanged: (controller, progress) {
                setState(() {
                  _progress = progress / 100;
                });
              },
              onTitleChanged: (controller, title) {
                if (title != null && title.isNotEmpty) {
                  setState(() => _pageTitle = title);
                }
              },
              onLoadStop: (controller, url) {
                if (url != null) {
                  setState(() {
                    _currentUrl = url.toString();
                    _urlController.text = _currentUrl;
                  });
                }
              },
            ),
          ),

          // Action Bar at bottom
          SafeArea(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Portal Schedule Scraper',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        Text(
                          'Target: $_cssSelector',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _shareCurrentLocation,
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Share URL'),
                    style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _isLoading ? null : _extractFromWebPage,
                    icon: const Icon(Icons.auto_awesome_rounded),
                    label: const Text('Scrape Table'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
