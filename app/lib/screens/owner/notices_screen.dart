import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/back_nav.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../data/owner_repo.dart';
import '../../theme.dart';
import '../../widgets/common.dart';

/// More → Notice to students (20 Oct 2026):
///  - "Students see now": notices from the last 30 days, each with 🗑 remove
///  - 6 big boxes (Water off / Power cut / Cleaning / Rent reminder / Food timing / Other) that fill a heading
///    and a short message the owner can change
///  - Send to all students
/// With no notice, students see the default "Keep the hostel clean" message (made in the student app).
class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key, required this.hostelId});
  final String hostelId;

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class NoticeType {
  const NoticeType(this.code, this.icon, this.color);
  final String code;
  final IconData icon;
  final Color color;
}

const noticeTypes = [
  NoticeType('water', Icons.water_drop_outlined, Color(0xFF0E7490)),
  NoticeType('power', Icons.bolt_rounded, Color(0xFFB45309)),
  NoticeType('cleaning', Icons.cleaning_services_outlined, Color(0xFF15803D)),
  NoticeType('rent', Icons.currency_rupee_rounded, AppColors.primary),
  NoticeType('food', Icons.restaurant_outlined, Color(0xFFB0306A)),
  NoticeType('other', Icons.campaign_outlined, Color(0xFF534AB7)),
];

NoticeType noticeTypeOf(String? code) => noticeTypes.firstWhere((n) => n.code == code, orElse: () => noticeTypes.last);

String noticeTitle(BuildContext context, String code) {
  final t = context.l10n;
  return switch (code) {
    'water' => t.noticeWater,
    'power' => t.noticePower,
    'cleaning' => t.noticeCleaning,
    'rent' => t.noticeRent,
    'food' => t.noticeFood,
    _ => t.noticeOther,
  };
}

String _noticeBody(BuildContext context, String code) {
  final t = context.l10n;
  return switch (code) {
    'water' => t.noticeWaterBody,
    'power' => t.noticePowerBody,
    'cleaning' => t.noticeCleaningBody,
    'rent' => t.noticeRentBody,
    'food' => t.noticeFoodBody,
    _ => '',
  };
}

class _NoticesScreenState extends State<NoticesScreen> {
  final _loader = GlobalKey<LoaderState<List<Json>>>();
  final _title = TextEditingController();
  final _body = TextEditingController();
  String? _type;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  void _pick(String code) {
    setState(() {
      _type = code;
      _title.text = code == 'other' ? '' : noticeTitle(context, code);
      _body.text = _noticeBody(context, code);
    });
  }

  Future<void> _send() async {
    final t = context.l10n;
    if (_title.text.trim().isEmpty) {
      showSnack(context, '${t.headingLabel}: ${t.cantBeEmpty}', error: true);
      return;
    }
    await OwnerRepo.instance.postNotice(widget.hostelId, icon: _type ?? 'other', title: _title.text.trim(), body: _body.text.trim());
    if (!mounted) return;
    setState(() {
      _type = null;
      _title.clear();
      _body.clear();
    });
    showSnack(context, t.noticePosted);
    await _loader.currentState?.reload();
  }

  Future<void> _remove(Json n) async {
    final t = context.l10n;
    final ok = await confirm(context, title: t.removeNoticeQ, message: t.removeNoticeText, okLabel: t.remove, danger: true);
    if (!ok || !mounted) return;
    try {
      await OwnerRepo.instance.removeNotice(n['id'] as String);
      await _loader.currentState?.reload();
    } catch (e) {
      if (mounted) showSnack(context, errorText(context, e), error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(t.noticeToStudents), leading: const AppBackButton()),
      body: Loader<List<Json>>(
        key: _loader,
        load: () => OwnerRepo.instance.ownerNotices(widget.hostelId),
        builder: (context, notices, reload) => PageList(
          onRefresh: reload,
          children: [
            SectionCard(
              title: t.studentsSeeNow,
              child: notices.isEmpty
                  ? Text(t.noNoticeNow, style: const TextStyle(color: AppColors.muted))
                  : Column(children: [
                      for (final n in notices)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _TypeIcon(type: noticeTypeOf(n['icon'] as String?)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(n['title'] as String? ?? '', style: const TextStyle(fontWeight: FontWeight.w600)),
                                if ((n['body'] as String?)?.isNotEmpty == true)
                                  Text(n['body'] as String, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                                Text(dateText(context, n['created_at']),
                                    style: const TextStyle(color: AppColors.muted, fontSize: 11)),
                              ]),
                            ),
                            IconButton(
                              tooltip: t.remove,
                              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.danger),
                              onPressed: () => _remove(n),
                            ),
                          ]),
                        ),
                    ]),
            ),
            SectionCard(
              title: t.newNotice,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(t.pickNoticeType, style: const TextStyle(color: AppColors.muted, fontSize: 12.5)),
                const SizedBox(height: 8),
                GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.15,
                  children: [
                    for (final n in noticeTypes)
                      Material(
                        color: _type == n.code ? n.color.withValues(alpha: 0.12) : Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: _type == n.code ? n.color : AppColors.line, width: _type == n.code ? 2 : 1),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () => _pick(n.code),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _TypeIcon(type: n),
                            const SizedBox(height: 6),
                            Text(noticeTitle(context, n.code),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _title,
                  textCapitalization: TextCapitalization.sentences,
                  inputFormatters: [LengthLimitingTextInputFormatter(80)],
                  decoration: InputDecoration(labelText: t.headingLabel),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _body,
                  textCapitalization: TextCapitalization.sentences,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 300,
                  decoration: InputDecoration(labelText: t.messageLabel),
                ),
                const SizedBox(height: 6),
                BusyButton(label: t.sendToAllStudents, icon: Icons.send_rounded, onPressed: _send),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeIcon extends StatelessWidget {
  const _TypeIcon({required this.type});
  final NoticeType type;

  @override
  Widget build(BuildContext context) => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: type.color, shape: BoxShape.circle),
        child: Icon(type.icon, size: 19, color: Colors.white),
      );
}
