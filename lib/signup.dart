import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  final TextEditingController confirmPasswordController =
      TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool isLoading = false;
  bool _obscurePass = true;
  bool _obscureConfirmPass = true;
  int passwordScore = 0;

  late AnimationController _controller;
  late Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _fadeIn = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your email';

    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@(gmail\.com|yahoo\.com|paterostechnologicalcollege\.edu\.ph)$',
    );
    if (!emailRegex.hasMatch(value))
      return 'Please enter a valid email address';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Please enter your password';
    if (value.length < 8) return 'Password must be at least 8 characters';
    if (!RegExp(r'[A-Z]').hasMatch(value))
      return 'Must contain an uppercase letter';
    if (!RegExp(r'[a-z]').hasMatch(value))
      return 'Must contain a lowercase letter';
    if (!RegExp(r'[0-9]').hasMatch(value)) return 'Must contain a number';
    if (!RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(value))
      return 'Must contain a special character';
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != passwordController.text) return "Passwords do not match";
    return null;
  }

  int calculatePasswordStrength(String password) {
    int score = 0;
    if (password.length >= 8) score++;
    if (RegExp(r'[A-Z]').hasMatch(password)) score++;
    if (RegExp(r'[a-z]').hasMatch(password)) score++;
    if (RegExp(r'[0-9]').hasMatch(password)) score++;
    if (RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password)) score++;
    return score;
  }

  Color getPasswordStrengthColor(int score) {
    switch (score) {
      case 0:
      case 1:
        return Colors.red;
      case 2:
        return Colors.orange;
      case 3:
        return Colors.yellow;
      case 4:
        return Colors.lightGreen;
      case 5:
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String getPasswordStrengthText(int score) {
    switch (score) {
      case 0:
      case 1:
        return "Very Weak";
      case 2:
        return "Weak";
      case 3:
        return "Medium";
      case 4:
        return "Strong";
      case 5:
        return "Very Strong";
      default:
        return "";
    }
  }

  bool isPasswordStrongEnough() => passwordScore >= 3;

  void registerUser() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => isLoading = true);

    String email = emailController.text.trim();
    String password = passwordController.text.trim();

    try {
      UserCredential userCredential = await FirebaseAuth.instance
          .createUserWithEmailAndPassword(email: email, password: password);

      await userCredential.user!.sendEmailVerification();

      await FirebaseFirestore.instance
          .collection('users')
          .doc(userCredential.user?.uid)
          .set({
            'email': email,
            'uid': userCredential.user?.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'emailVerified': false,
          });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              "Account created! Please check your email to verify.",
            ),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message ?? "Registration failed"),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue.shade100, Colors.white],
          ),
        ),
        child: FadeTransition(
          opacity: _fadeIn,
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Hero(
                    tag: "logo",
                    child: CircleAvatar(
                      radius: 45,
                      backgroundColor: Colors.white,
                      child: Icon(
                        Icons.water_drop,
                        size: 55,
                        color: Colors.blue,
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.blue.withOpacity(0.1),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        children: [
                          const Text(
                            "Create Account",
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(height: 24),

                          TextFormField(
                            controller: emailController,
                            validator: _validateEmail,
                            keyboardType: TextInputType.emailAddress,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'Email',
                              filled: true,
                              fillColor: Colors.blue.shade50.withOpacity(0.5),
                              prefixIcon: const Icon(
                                Icons.email_outlined,
                                color: Colors.blue,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.blue.shade100,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Colors.blue,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),

                          TextFormField(
                            controller: passwordController,
                            validator: _validatePassword,
                            obscureText: _obscurePass,
                            onChanged:
                                (value) => setState(
                                  () =>
                                      passwordScore = calculatePasswordStrength(
                                        value,
                                      ),
                                ),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'Password',
                              filled: true,
                              fillColor: Colors.blue.shade50.withOpacity(0.5),
                              prefixIcon: const Icon(
                                Icons.lock_outline,
                                color: Colors.blue,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePass
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                ),
                                onPressed:
                                    () => setState(
                                      () => _obscurePass = !_obscurePass,
                                    ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.blue.shade100,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Colors.blue,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 16),
                            child: Row(
                              children: [
                                Expanded(
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(5),
                                    child: LinearProgressIndicator(
                                      value: passwordScore / 5,
                                      color: getPasswordStrengthColor(
                                        passwordScore,
                                      ),
                                      backgroundColor: Colors.grey.shade200,
                                      minHeight: 6,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  getPasswordStrengthText(passwordScore),
                                  style: TextStyle(
                                    color: getPasswordStrengthColor(
                                      passwordScore,
                                    ),
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          TextFormField(
                            controller: confirmPasswordController,
                            validator: _validateConfirmPassword,
                            obscureText: _obscureConfirmPass,
                            style: const TextStyle(fontWeight: FontWeight.w500),
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              filled: true,
                              fillColor: Colors.blue.shade50.withOpacity(0.5),

                              prefixIcon: const Icon(
                                Icons.lock_outline,
                                color: Colors.blue,
                              ),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPass
                                      ? Icons.visibility_off
                                      : Icons.visibility,
                                  color: Colors.grey,
                                ),
                                onPressed:
                                    () => setState(
                                      () =>
                                          _obscureConfirmPass =
                                              !_obscureConfirmPass,
                                    ),
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                  color: Colors.blue.shade100,
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                  color: Colors.blue,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),

                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed:
                                  isLoading || !isPasswordStrongEnough()
                                      ? null
                                      : registerUser,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue,
                                foregroundColor: Colors.white,
                                elevation: 3,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child:
                                  isLoading
                                      ? const SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 2,
                                        ),
                                      )
                                      : const Text(
                                        "Sign Up",
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        "Already have an account? ",
                        style: TextStyle(color: Colors.black54),
                      ),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          "Login",
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
