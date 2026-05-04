import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../utils/alert_meta.dart';

const adminNavy = AppColors.navy;
const adminNavyLt = AppColors.navyLight;
const adminRed = AppColors.red;
const adminWhite = AppColors.white;
const adminBorder = AppColors.border;
const adminMuted = AppColors.muted;
const adminText = AppColors.text;
const adminGreen = AppColors.green;
const adminGreenLt = AppColors.greenLight;
const adminOrange = AppColors.orange;
const adminBlue = AppColors.blue;

Color adminTypeColor(BuildContext context, String type) =>
    typeMeta(type, context.appTheme).color;

String adminTypeLabel(BuildContext context, String type) =>
    typeMeta(type, context.appTheme).label;

IconData adminTypeIcon(BuildContext context, String type) =>
    typeMeta(type, context.appTheme).icon;

String formatAdminDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

String formatAdminTimestamp(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} '
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String formatAdminMinutes(int min) =>
    min < 60 ? '${min}m' : '${min ~/ 60}h ${min % 60}m';
