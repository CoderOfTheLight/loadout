import 'package:flutter/material.dart';

void main() => runApp(const LoadoutApp());

class LoadoutApp extends StatelessWidget {
  const LoadoutApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Loadout',
    debugShowCheckedModeBanner: false,
    themeMode: ThemeMode.system,
    theme: _theme(Brightness.light),
    darkTheme: _theme(Brightness.dark),
    home: const WelcomeScreen(),
  );

  ThemeData _theme(Brightness brightness) => ThemeData(
    brightness: brightness,
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xff356859),
      brightness: brightness,
    ),
  );
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.inventory_2_outlined,
                  size: 72,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 32),
                Text(
                  'Plan what to bring. Learn from what happened.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 16),
                Text(
                  'Loadout keeps your events, inventory, recipes, and forecasts '
                  'on this device. Nothing is uploaded.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                const SizedBox(height: 32),
                Semantics(
                  label: 'Create a private local workspace',
                  button: true,
                  child: FilledButton(
                    onPressed: () {},
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 56),
                    ),
                    child: const Text('Create workspace'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
