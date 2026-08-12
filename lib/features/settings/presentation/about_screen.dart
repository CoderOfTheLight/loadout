/// `/settings/about` (design §9): app name + version (the workspace_meta
/// seed constant — no runtime package lookup in v1), the forecast method
/// registry, and open-source licenses via [showLicensePage] (the SQLCipher
/// BSD-style license is registered here).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/widgets/content_column.dart';
import '../../../data/db/app_database.dart' show seedAppVersion;
import '../../forecasting/domain/snapshot.dart';

/// SQLCipher Community Edition license (BSD-style), shown in the license
/// registry because the native library is linked, not a pub package.
const String _sqlcipherLicense = '''
Copyright (c) 2008-2012 Zetetic LLC. All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:
- Redistributions of source code must retain the above copyright notice,
  this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice,
  this list of conditions and the following disclaimer in the documentation
  and/or other materials provided with the distribution.
- Neither the name of the ZETETIC LLC nor the names of its contributors may
  be used to endorse or promote products derived from this software without
  specific prior written permission.

THIS SOFTWARE IS PROVIDED BY ZETETIC LLC ''AS IS'' AND ANY EXPRESS OR
IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN
NO EVENT SHALL ZETETIC LLC BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
''';

bool _sqlcipherLicenseRegistered = false;

void _registerSqlcipherLicense() {
  if (_sqlcipherLicenseRegistered) return;
  _sqlcipherLicenseRegistered = true;
  LicenseRegistry.addLicense(
    () => Stream<LicenseEntry>.value(
      const LicenseEntryWithLineBreaks(['SQLCipher'], _sqlcipherLicense),
    ),
  );
}

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('About')),
      body: SafeArea(
        child: SingleChildScrollView(
          child: ContentColumn(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 16),
                Icon(
                  Icons.inventory_2_outlined,
                  size: 56,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 12),
                Text(
                  'Loadout',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall,
                ),
                Text(
                  'Version $seedAppVersion',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Private, offline event inventory and forecasting.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                Text('Forecast methods', style: theme.textTheme.titleSmall),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.insights_outlined),
                    title: Text(
                      '$forecastMethodDirectMedian — '
                      'v$forecastMethodVersion — since 2026-08',
                    ),
                    subtitle: const Text(
                      'Median depletion rate over recent closed events, '
                      'plus the plan policy reserve.',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('Open-source licenses'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      _registerSqlcipherLicense();
                      showLicensePage(
                        context: context,
                        applicationName: 'Loadout',
                        applicationVersion: seedAppVersion,
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
