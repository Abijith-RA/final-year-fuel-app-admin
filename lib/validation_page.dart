import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:uuid/uuid.dart';

class ValidationPage extends StatefulWidget {
  const ValidationPage({super.key});

  @override
  State<ValidationPage> createState() => _ValidationPageState();
}

class _ValidationPageState extends State<ValidationPage> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();
  bool _isFirebaseInitialized = false;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _initializeFirebase();
  }

  Future<void> _initializeFirebase() async {
    try {
      await Firebase.initializeApp();
      setState(() {
        _isFirebaseInitialized = true;
      });
    } catch (e) {
      print("Firebase initialization error: $e");
    }
  }

  String _generatePassword() {
    // Generate a unique password with pattern AAAAAAA1 (7 letters + 1 number)
    final randomPart = _uuid.v4().substring(0, 7).toUpperCase();
    return '${randomPart}1';
  }

  @override
  Widget build(BuildContext context) {
    if (!_isFirebaseInitialized) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.orange)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Validation', style: TextStyle(color: Colors.orange)),
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.orange),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _firestore.collection('deliboyrequest').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.orange),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Text(
                'No registration requests found',
                style: TextStyle(color: Colors.orange),
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final doc = snapshot.data!.docs[index];
              final data = doc.data() as Map<String, dynamic>;

              return Card(
                color: Colors.grey[900],
                margin: const EdgeInsets.only(bottom: 16),
                child: InkWell(
                  onTap: () {
                    if (data['status']?.toLowerCase() == 'pending') {
                      _startValidationProcess(context, doc.id, data);
                    } else if (data['status']?.toLowerCase() ==
                        'under validation') {
                      // If status is "under validation", show the decision dialog directly
                      _showDecisionDialog(context, doc.id, data);
                    } else {
                      _showDetailsDialog(context, data);
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          data['name'] ?? 'No Name',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          data['email'] ?? 'No Email',
                          style: const TextStyle(
                            color: Colors.orange,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Chip(
                          label: Text(
                            data['status']?.toString().toUpperCase() ??
                                'UNKNOWN',
                            style: const TextStyle(color: Colors.white),
                          ),
                          backgroundColor: _getStatusColor(data['status']),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Color _getStatusColor(String? status) {
    switch (status?.toLowerCase()) {
      case 'pending':
        return Colors.blue;
      case 'under validation':
        return Colors.orange;
      case 'verified':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  Future<void> _startValidationProcess(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) async {
    try {
      // First update status to "under validation"
      await _firestore.collection('deliboyrequest').doc(docId).update({
        'status': 'under validation',
      });

      // Then show the decision dialog
      if (mounted) {
        _showDecisionDialog(context, docId, data);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error starting validation: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showDecisionDialog(
    BuildContext context,
    String docId,
    Map<String, dynamic> data,
  ) {
    bool isProcessing = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return WillPopScope(
              onWillPop: () async {
                if (isProcessing) {
                  _showCannotGoBackWarning(context);
                  return false;
                }
                return true;
              },
              child: AlertDialog(
                backgroundColor: Colors.grey[900],
                title: Text(
                  'Application Review',
                  style: TextStyle(color: Colors.orange),
                ),
                content: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildDetailRow('Name', data['name']),
                      _buildDetailRow('Email', data['email']),
                      _buildDetailRow('Date of Birth', data['dob']),
                      _buildDetailRow('Age', data['age']?.toString()),
                      _buildDetailRow(
                        'Employment Type',
                        data['employmentType'],
                      ),
                      const SizedBox(height: 16),
                      if (data['timestamp'] != null)
                        _buildDetailRow(
                          'Application Date',
                          _formatTimestamp(data['timestamp']),
                        ),
                      _buildDetailRow('Current Status', data['status']),
                    ],
                  ),
                ),
                actions: [
                  if (isProcessing)
                    const CircularProgressIndicator(color: Colors.orange)
                  else ...[
                    TextButton(
                      onPressed: () async {
                        setState(() => isProcessing = true);
                        await _processApplication(docId, data, 'cancelled');
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text(
                        'REJECT',
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                      onPressed: () async {
                        setState(() => isProcessing = true);
                        await _processApplication(docId, data, 'verified');
                        if (mounted) Navigator.pop(context);
                      },
                      child: const Text(
                        'ACCEPT',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _processApplication(
    String docId,
    Map<String, dynamic> data,
    String status,
  ) async {
    try {
      setState(() => _isProcessing = true);

      // Create a new map without the status field
      final newData = Map<String, dynamic>.from(data);
      newData.remove('status');

      // Update the status in the original document
      await _firestore.collection('deliboyrequest').doc(docId).update({
        'status': status,
        'processedAt': FieldValue.serverTimestamp(),
      });

      // Determine which collection to move to
      String targetCollection =
          status == 'verified' ? 'Rapidboy' : 'rejectedboys';

      // Prepare data for the target collection
      final targetData = {
        ...newData,
        'processedAt': FieldValue.serverTimestamp(),
      };

      // For Rapidboy collection, add a generated password
      if (status == 'verified') {
        targetData['password'] = _generatePassword();
      }

      // Add to the target collection
      await _firestore.collection(targetCollection).doc(docId).set(targetData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Application ${status == 'verified' ? 'verified' : 'cancelled'} successfully',
            ),
            backgroundColor: status == 'verified' ? Colors.green : Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error processing application: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      setState(() => _isProcessing = false);
    }
  }

  void _showCannotGoBackWarning(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Please complete the validation process first'),
        backgroundColor: Colors.orange,
      ),
    );
  }

  void _showDetailsDialog(BuildContext context, Map<String, dynamic> data) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            'Application Details',
            style: TextStyle(color: Colors.orange),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDetailRow('Name', data['name']),
                _buildDetailRow('Email', data['email']),
                _buildDetailRow('Date of Birth', data['dob']),
                _buildDetailRow('Age', data['age']?.toString()),
                _buildDetailRow('Employment Type', data['employmentType']),
                _buildDetailRow('Status', data['status']),
                const SizedBox(height: 16),
                if (data['timestamp'] != null)
                  _buildDetailRow(
                    'Application Date',
                    _formatTimestamp(data['timestamp']),
                  ),
                if (data['processedAt'] != null)
                  _buildDetailRow(
                    'Processed Date',
                    _formatTimestamp(data['processedAt']),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'CLOSE',
                style: TextStyle(color: Colors.orange),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          Expanded(
            child: Text(
              value ?? 'Not provided',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimestamp(dynamic timestamp) {
    if (timestamp == null) return 'Unknown';

    try {
      if (timestamp is Timestamp) {
        return DateTime.fromMillisecondsSinceEpoch(
          timestamp.millisecondsSinceEpoch,
        ).toString();
      }
      return timestamp.toString();
    } catch (e) {
      return 'Invalid date';
    }
  }
}
