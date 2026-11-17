import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({super.key, required this.child});
  final Widget child;
  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> with WidgetsBindingObserver {
  bool unlocked = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      if (unlocked) setState(() => unlocked = false);
    }
  }

  @override
  Widget build(BuildContext context) => unlocked
      ? widget.child
      : LoginPage(onSuccess: () => setState(() => unlocked = true));
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.onSuccess});
  final VoidCallback onSuccess;
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const channel = MethodChannel('swifty_protein/auth');
  final username = TextEditingController();
  final password = TextEditingController();
  bool hasAccount = true, biometric = false, busy = false, register = false;
  String? error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final account = await channel.invokeMethod<bool>('hasAccount') ?? false;
      final available =
          await channel.invokeMethod<bool>('biometricAvailable') ?? false;
      if (mounted)
        setState(() {
          hasAccount = account;
          register = !account;
          biometric = available;
        });
    } on PlatformException catch (e) {
      if (mounted)
        setState(() => error = e.message ?? 'Authentication is unavailable.');
    }
  }

  Future<void> _submit(String method) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await channel.invokeMethod<bool>(
        method,
        method == 'biometricLogin'
            ? null
            : {'username': username.text, 'password': password.text},
      );
      password.clear();
      if (mounted) widget.onSuccess();
    } on PlatformException catch (e) {
      if (mounted)
        setState(() => error = e.message ?? 'Authentication failed.');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    username.dispose();
    password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.bubble_chart,
                    size: 72,
                    color: Color(0xff37c9bb),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    register ? 'Create an account' : 'Welcome back',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: username,
                    enabled: !busy,
                    autocorrect: false,
                    decoration: const InputDecoration(
                      labelText: 'Username',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    enabled: !busy,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      helperText: register ? 'At least 12 characters' : null,
                      border: const OutlineInputBorder(),
                    ),
                    onSubmitted: (_) =>
                        _submit(register ? 'register' : 'login'),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: busy
                        ? null
                        : () => _submit(register ? 'register' : 'login'),
                    child: Text(register ? 'Create account' : 'Log in'),
                  ),
                  if (!register && biometric)
                    TextButton.icon(
                      onPressed: busy ? null : () => _submit('biometricLogin'),
                      icon: const Icon(Icons.fingerprint),
                      label: const Text('Use biometrics'),
                    ),
                  if (hasAccount)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() {
                              register = !register;
                              error = null;
                            }),
                      child: Text(
                        register
                            ? 'Already have an account? Log in'
                            : 'Create another account',
                      ),
                    ),
                  if (busy)
                    const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
