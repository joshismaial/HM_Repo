import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:go_router/go_router.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/back_nav.dart';
import '../../config.dart';
import '../../core/format.dart';
import '../../theme.dart';
import '../../widgets/common.dart';
import 'hostel_scope.dart';

/// Saves the hostel's join QR code (white background, hostel name underneath) to the gallery.
Future<void> downloadJoinQr(BuildContext context, Json hostel) async {
  final t = context.l10n;
  final link = AppConfig.joinLink(hostel['join_code'] as String);
  if (kIsWeb) {
    // The owner app runs on Android; on the web just copy the link instead.
    await copyText(context, link);
    return;
  }
  try {
    const size = 1024.0, pad = 64.0, label = 96.0;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, size, size + label), Paint()..color = Colors.white);
    canvas.translate(pad, pad);
    QrPainter(data: link, version: QrVersions.auto, gapless: true).paint(canvas, const Size(size - 2 * pad, size - 2 * pad));
    canvas.translate(-pad, -pad);
    final tp = TextPainter(
      text: TextSpan(
        text: '${hostel['name']}',
        style: const TextStyle(color: Colors.black, fontSize: 44, fontWeight: FontWeight.w800),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: size - 2 * pad);
    tp.paint(canvas, Offset((size - tp.width) / 2, size - pad / 2));
    final image = await recorder.endRecording().toImage(size.toInt(), (size + label).toInt());
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    if (png == null) throw StateError('no image');
    if (!await Gal.hasAccess()) await Gal.requestAccess();
    await Gal.putImageBytes(png.buffer.asUint8List(), name: 'hostel_qr_${hostel['join_code']}');
    if (context.mounted) showSnack(context, t.qrSaved);
  } catch (_) {
    if (context.mounted) showSnack(context, t.qrSaveFailed, error: true);
  }
}

/// Join QR code and link for students (shown on Home and on "Invite students").
class JoinCard extends StatelessWidget {
  const JoinCard({super.key, required this.hostel, this.large = false});
  final Json hostel;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final link = AppConfig.joinLink(hostel['join_code'] as String);
    final closed = hostel['is_open'] != true;
    return SectionCard(
      title: t.joinQrTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (closed) Banner2(text: t.hostelClosedNote, tone: Tone.warning),
          Text(t.joinQrHelp, style: const TextStyle(color: AppColors.muted)),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(border: Border.all(color: AppColors.line), borderRadius: BorderRadius.circular(12)),
              child: QrImageView(data: link, size: large ? 240 : 160, backgroundColor: Colors.white),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.download_rounded, size: 18),
              label: Text(t.downloadQr),
              onPressed: () => downloadJoinQr(context, hostel),
            ),
          ),
          const SizedBox(height: 10),
          SelectableText(link, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 18),
                  label: Text(t.copyLink),
                  onPressed: () => copyText(context, link),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.whatsapp),
                  icon: const Icon(Icons.share_rounded, size: 18),
                  label: Text(t.shareWhatsapp),
                  onPressed: () => launchUrl(
                    Uri.parse('https://wa.me/?text=${Uri.encodeComponent(t.inviteMessage(hostelTitle(context, hostel), link))}'),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
              ),
            ],
          ),
          if (!large)
            TextButton(
              onPressed: () => context.go('/h/${hostel['id']}/invite'),
              child: Text(t.showBigQr),
            ),
        ],
      ),
    );
  }
}

class InviteScreen extends StatelessWidget {
  const InviteScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    final h = HostelScope.of(context).hostel;
    return Scaffold(
      appBar: AppBar(
        title: Text(t.inviteStudents),
        leading: const AppBackButton(),
      ),
      body: h == null
          ? const Center(child: CircularProgressIndicator())
          : PageList(children: [
              JoinCard(hostel: h, large: true),
              Banner2(text: t.printQrTip, icon: Icons.print_rounded),
            ]),
    );
  }
}
