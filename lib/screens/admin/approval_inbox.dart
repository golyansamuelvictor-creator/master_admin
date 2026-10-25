// ignore_for_file: curly_braces_in_flow_control_structures
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/workflow_logic.dart';
import 'package:master_admin/core/app_palette.dart';

class ApprovalInbox extends StatefulWidget {
  final String userRole;
  const ApprovalInbox({super.key, required this.userRole});

  @override
  State<ApprovalInbox> createState() => _ApprovalInboxState();
}

class _ApprovalInboxState extends State<ApprovalInbox> {
  final _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  List<dynamic> _myPendingRequests = [];
  final Set<dynamic> _readRequestIds = {};
  bool _isLoading = true;
  String _searchQuery = '';
  final Color pPurple = const Color(0xFF4A148C);

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRequests() async {
    setState(() => _isLoading = true);
    try {
      // 1. Identify which workflow stage the user belongs to
      String? myLevel = TransferWorkflow.getRoleLevel(widget.userRole);
      if (myLevel == null) return;

      // 2. Fetch requests currently at this level
      final res = await _supabase
          .from('transfer_requests')
          .select('*, members(english_name)')
          .eq('current_level', myLevel)
          .eq('status', 'pending');

      setState(() {
        _myPendingRequests = res;
        for (final req in res) {
          if (req['is_read'] == true) {
            _readRequestIds.add(req['id']);
          }
        }
      });
    } catch (e) {
      debugPrint("Error loading inbox: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _markAsRead(dynamic reqId) {
    if (!_readRequestIds.contains(reqId)) {
      setState(() => _readRequestIds.add(reqId));
      // Safely attempt to persist read status if 'is_read' column exists
      _supabase
          .from('transfer_requests')
          .update({'is_read': true})
          .eq('id', reqId)
          .then((_) {})
          .catchError((_) {});
    }
  }

  void _markAsUnread(dynamic reqId) {
    if (_readRequestIds.contains(reqId)) {
      setState(() => _readRequestIds.remove(reqId));
      _supabase
          .from('transfer_requests')
          .update({'is_read': false})
          .eq('id', reqId)
          .then((_) {})
          .catchError((_) {});
    }
  }

  Future<void> _signRequest(dynamic request, bool approved) async {
    final String? myLevel = TransferWorkflow.getRoleLevel(widget.userRole);
    if (myLevel == null) {
      // Not a signer for transfers (this used to crash on `myLevel as Object`)
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Your role can't sign transfer requests.")),
      );
      return;
    }

    try {
      // 1. Record the signature
      await _supabase.from('transfer_approvals').insert({
        'request_id': request['id'],
        'approver_id': _supabase.auth.currentUser!.id,
        'approver_role': widget.userRole,
        'approval_level': myLevel,
        'decision': approved ? 'approved' : 'rejected',
      });

      if (!approved) {
        // If one person rejects, the whole request stops
        await _supabase
            .from('transfer_requests')
            .update({'status': 'rejected'})
            .eq('id', request['id']);
      } else {
        // 2. Check if this level is now finished (e.g. Dept Sec + Dept Lead both signed)
        final signatures = await _supabase
            .from('transfer_approvals')
            .select('approver_role')
            .eq('request_id', request['id'])
            .eq('approval_level', myLevel);

        List<String> rolesWhoSigned =
            signatures.map((s) => s['approver_role'].toString()).toList();

        if (TransferWorkflow.isLevelComplete(myLevel, rolesWhoSigned)) {
          // Level is complete! Move to next level OR execute if IA
          String? nextLevel = TransferWorkflow.getNextLevel(myLevel);

          if (nextLevel == null) {
            // Final level (Internal Affairs) -> execute changes
            await _executeMemberTransfer(request);
          } else {
            // Move to next stage (e.g. from Dept to Sub-Location)
            await _supabase
                .from('transfer_requests')
                .update({'current_level': nextLevel})
                .eq('id', request['id']);
          }
        }
      }

      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Decision recorded")),
      );
      _loadRequests();
    } catch (e) {
      debugPrint("Approval Error: $e");
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't record your decision. Please try again.")),
      );
    }
  }

  Future<void> _executeMemberTransfer(dynamic request) async {
    final newUnit = request['new_unit_details'];
    final oldUnit = request['old_unit_details'];
    String? pick(dynamic unit, String key, String legacy) {
      if (unit is! Map) return null;
      final v = unit[key] ?? unit[legacy];
      return v?.toString();
    }

    // Update the member's unit. The request stores location / sub_location /
    // department / team / cell_group (the old code read 'loc' and wrote
    // team_number / cell_number, which don't exist on members).
    final Map<String, dynamic> update = {
      'location': pick(newUnit, 'location', 'loc'),
      'sub_location': pick(newUnit, 'sub_location', 'sub'),
      'department': pick(newUnit, 'department', 'dept'),
      'team': pick(newUnit, 'team', 'team'),
      'cell_group': pick(newUnit, 'cell_group', 'cell'),
    }..removeWhere((k, v) => v == null || v.isEmpty);
    if (update.isNotEmpty) {
      await _supabase.from('members').update(update).eq('id', request['member_id']);
    }

    // Keep a history row in member_transfers
    try {
      await _supabase.from('member_transfers').insert({
        'member_id': request['member_id'],
        'old_location': pick(oldUnit, 'location', 'loc'),
        'old_sub_location': pick(oldUnit, 'sub_location', 'sub'),
        'old_dept': pick(oldUnit, 'department', 'dept'),
        'old_team': pick(oldUnit, 'team', 'team'),
        'old_cell': pick(oldUnit, 'cell_group', 'cell'),
        'new_location': update['location'],
        'new_sub_location': update['sub_location'],
        'new_dept': update['department'],
        'new_team': update['team'],
        'new_cell': update['cell_group'],
        'transfer_date': DateTime.now().toIso8601String().substring(0, 10),
        'reason': request['reason'],
        'authorized_by': _supabase.auth.currentUser?.id,
      });
    } catch (e) {
      debugPrint("Transfer history insert failed: $e");
    }

    await _supabase
        .from('transfer_requests')
        .update({'status': 'completed'})
        .eq('id', request['id']);
  }

  // --- Helpers for Sender, Date, and Search ---

  String _getSender(dynamic req) {
    if (req['sender_name'] != null && req['sender_name'].toString().isNotEmpty) {
      return req['sender_name'].toString();
    }
    if (req['submitted_by'] != null && req['submitted_by'].toString().isNotEmpty) {
      return req['submitted_by'].toString();
    }
    final oldU = req['old_unit_details'];
    if (oldU is Map && oldU['loc'] != null) {
      return "Unit ${oldU['loc']}${oldU['team'] != null ? ' (Team ${oldU['team']})' : ''}";
    }
    return "Branch Origin";
  }

  String _formatDate(dynamic dateRaw) {
    if (dateRaw == null) return "No date";
    DateTime? dt;
    if (dateRaw is DateTime) {
      dt = dateRaw;
    } else {
      dt = DateTime.tryParse(dateRaw.toString());
    }
    if (dt == null) return dateRaw.toString();

    final local = dt.toLocal();
    final now = DateTime.now();
    final isToday =
        local.year == now.year && local.month == now.month && local.day == now.day;

    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final monthStr = months[local.month - 1];
    final hour = local.hour == 0 ? 12 : (local.hour > 12 ? local.hour - 12 : local.hour);
    final minute = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    final timeStr = "$hour:$minute $ampm";

    if (isToday) return "Today, $timeStr";
    return "$monthStr ${local.day}, ${local.year} · $timeStr";
  }

  String _formatDateShort(dynamic dateRaw) {
    if (dateRaw == null) return "";
    DateTime? dt;
    if (dateRaw is DateTime) {
      dt = dateRaw;
    } else {
      dt = DateTime.tryParse(dateRaw.toString());
    }
    if (dt == null) return dateRaw.toString();
    final local = dt.toLocal();
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return "${months[local.month - 1]} ${local.day}, ${local.year}";
  }

  bool _matchesSearch(dynamic req, String query) {
    if (query.isEmpty) return true;
    final q = query.toLowerCase().trim();

    final memberName = req['members']?['english_name']?.toString().toLowerCase() ?? '';
    final sender = _getSender(req).toLowerCase();
    final level = req['current_level']?.toString().toLowerCase() ?? '';

    final rawDate = (req['created_at'] ?? req['date_sent'] ?? '').toString().toLowerCase();
    final formattedDate = _formatDate(req['created_at'] ?? req['date_sent']).toLowerCase();
    final shortDate = _formatDateShort(req['created_at'] ?? req['date_sent']).toLowerCase();

    final oldU = req['old_unit_details'] ?? {};
    final newU = req['new_unit_details'] ?? {};
    final oldLoc = oldU['loc']?.toString().toLowerCase() ?? '';
    final oldTeam = oldU['team']?.toString().toLowerCase() ?? '';
    final newLoc = newU['loc']?.toString().toLowerCase() ?? '';
    final newTeam = newU['team']?.toString().toLowerCase() ?? '';

    return memberName.contains(q) ||
        sender.contains(q) ||
        level.contains(q) ||
        rawDate.contains(q) ||
        formattedDate.contains(q) ||
        shortDate.contains(q) ||
        oldLoc.contains(q) ||
        oldTeam.contains(q) ||
        newLoc.contains(q) ||
        newTeam.contains(q);
  }

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      helpText: "Select date to filter",
    );
    if (picked != null) {
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      final formatted = "${months[picked.month - 1]} ${picked.day}, ${picked.year}";
      _searchController.text = formatted;
      setState(() => _searchQuery = formatted);
    }
  }

  // --- UI Builders ---

  @override
  Widget build(BuildContext context) {
    final filtered =
        _myPendingRequests.where((req) => _matchesSearch(req, _searchQuery)).toList();

    final unreadRequests = filtered
        .where((req) => !_readRequestIds.contains(req['id']) && req['is_read'] != true)
        .toList();

    final readRequests = filtered
        .where((req) => _readRequestIds.contains(req['id']) || req['is_read'] == true)
        .toList();

    final totalUnreadCount = _myPendingRequests
        .where((req) => !_readRequestIds.contains(req['id']) && req['is_read'] != true)
        .length;

    final totalReadCount = _myPendingRequests
        .where((req) => _readRequestIds.contains(req['id']) || req['is_read'] == true)
        .length;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppPalette.bg(Colors.grey.shade50),
        appBar: AppBar(
          centerTitle: true,
          elevation: 0.5,
          backgroundColor: AppPalette.bg(Colors.white),
          title: Text(
            "Governance Inbox",
            style: GoogleFonts.merriweather(
              fontWeight: FontWeight.bold,
              color: AppPalette.fg(pPurple),
              fontSize: 19,
            ),
          ),
          bottom: TabBar(
            labelColor: pPurple,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: pPurple,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.mark_email_unread_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text("Unread ($totalUnreadCount)"),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.mark_email_read_outlined, size: 18),
                    const SizedBox(width: 8),
                    Text("Read ($totalReadCount)"),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  _buildSearchBar(),
                  Expanded(
                    child: TabBarView(
                      children: [
                        _buildRequestList(unreadRequests, isUnreadTab: true),
                        _buildRequestList(readRequests, isUnreadTab: false),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppPalette.bg(Colors.white),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: "Search by keyword or date (e.g. John, Oct 24)...",
          hintStyle: TextStyle(fontSize: 13, color: AppPalette.fg(Colors.grey.shade500)),
          prefixIcon: Icon(Icons.search, color: AppPalette.fg(pPurple), size: 20),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchQuery.isNotEmpty)
                IconButton(
                  icon: Icon(Icons.clear, size: 18, color: AppPalette.fg(Colors.grey)),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                ),
              IconButton(
                icon: Icon(Icons.calendar_today_outlined, size: 18, color: AppPalette.fg(pPurple)),
                tooltip: "Filter by date",
                onPressed: _pickDateFilter,
              ),
            ],
          ),
          filled: true,
          fillColor: AppPalette.bg(Colors.grey.shade100),
          contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(25),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildRequestList(List<dynamic> requests, {required bool isUnreadTab}) {
    if (requests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadRequests,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    isUnreadTab
                        ? Icons.mark_email_read_outlined
                        : Icons.drafts_outlined,
                    size: 52,
                    color: AppPalette.fg(Colors.grey.shade400),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _searchQuery.isNotEmpty
                        ? "No matching requests found."
                        : isUnreadTab
                            ? "Your inbox is clear. No unread transfers."
                            : "No read messages in this folder.",
                    style: TextStyle(color: AppPalette.fg(Colors.grey.shade600), fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRequests,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: requests.length,
        itemBuilder: (c, i) => _buildMessageCard(requests[i], isUnreadTab),
      ),
    );
  }

  Widget _buildMessageCard(dynamic req, bool isUnread) {
    final oldU = req['old_unit_details'] ?? {};
    final newU = req['new_unit_details'] ?? {};
    final memberName = req['members']?['english_name'] ?? "Unknown Member";
    final sender = _getSender(req);
    final dateSent = _formatDate(req['created_at'] ?? req['date_sent']);

    return Card(
      elevation: isUnread ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: AppPalette.line(isUnread ? pPurple.withValues(alpha: 0.25) : Colors.grey.shade200),
          width: 1,
        ),
      ),
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          _markAsRead(req['id']);
          _showRequestDetailsBottomSheet(req);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Sender and Date Sent Row
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  CircleAvatar(
                    radius: 17,
                    backgroundColor:
                        AppPalette.bg(isUnread ? pPurple : Colors.grey.shade400),
                    child: Text(
                      sender.isNotEmpty ? sender[0].toUpperCase() : "T",
                      style: TextStyle(
                        color: AppPalette.fg(Colors.white),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                sender,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight:
                                      isUnread ? FontWeight.bold : FontWeight.w600,
                                  color: AppPalette.fg(Colors.black87),
                                ),
                              ),
                            ),
                            if (isUnread) ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: AppPalette.bg(pPurple),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          "Date sent: $dateSent",
                          style: TextStyle(
                            fontSize: 11,
                            color: AppPalette.fg(Colors.grey.shade600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppPalette.bg(Colors.blue.shade50),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      "Level: ${req['current_level'] ?? 'N/A'}",
                      style: TextStyle(
                        fontSize: 11,
                        color: AppPalette.fg(Colors.blue.shade800),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(height: 18),

              // Subject / Member Details
              Text(
                "Transfer Request: $memberName",
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                  color: AppPalette.fg(Colors.black87),
                ),
              ),
              const SizedBox(height: 6),

              // Transfer Route Preview
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppPalette.bg(Colors.grey.shade50),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "From: Loc ${oldU['loc'] ?? '-'}, Team ${oldU['team'] ?? '-'}",
                        style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(Icons.arrow_forward, size: 14, color: AppPalette.fg(Colors.grey)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "To: Loc ${newU['loc'] ?? '-'}, Team ${newU['team'] ?? '-'}",
                        style: TextStyle(fontSize: 12, color: AppPalette.fg(Colors.grey.shade700)),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Action Buttons
              _buildActionButtons(req),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(dynamic req) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => _signRequest(req, false),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppPalette.line(Colors.red)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            child: Text(
              "Reject",
              style: TextStyle(color: AppPalette.fg(Colors.red), fontWeight: FontWeight.w600),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ElevatedButton(
            onPressed: () => _signRequest(req, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.bg(Colors.green.shade700),
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              padding: const EdgeInsets.symmetric(vertical: 8),
            ),
            child: Text(
              "Approve & Sign",
              style: TextStyle(color: AppPalette.fg(Colors.white), fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  void _showRequestDetailsBottomSheet(dynamic req) {
    final oldU = req['old_unit_details'] ?? {};
    final newU = req['new_unit_details'] ?? {};
    final memberName = req['members']?['english_name'] ?? "Unknown Member";
    final sender = _getSender(req);
    final dateSent = _formatDate(req['created_at'] ?? req['date_sent']);
    final isRead = _readRequestIds.contains(req['id']);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppPalette.bg(Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Transfer Details",
                    style: GoogleFonts.merriweather(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppPalette.fg(pPurple),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      if (isRead) {
                        _markAsUnread(req['id']);
                      } else {
                        _markAsRead(req['id']);
                      }
                      Navigator.pop(context);
                    },
                    icon: Icon(
                      isRead ? Icons.mark_email_unread_outlined : Icons.mark_email_read_outlined,
                      size: 16,
                    ),
                    label: Text(
                      isRead ? "Mark as unread" : "Mark as read",
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const Divider(),
              Text("Sender / Origin: $sender",
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Text("Date sent: $dateSent",
                  style: TextStyle(color: AppPalette.fg(Colors.grey.shade600), fontSize: 12)),
              const SizedBox(height: 4),
              Text("Member: $memberName",
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 4),
              Text("Workflow level: ${req['current_level'] ?? 'N/A'}",
                  style: TextStyle(color: AppPalette.fg(Colors.grey.shade600), fontSize: 12)),
              const SizedBox(height: 16),

              // From / To Comparison Table
              Row(
                children: [
                  Expanded(
                    child: _unitInfoBox(
                      "From",
                      oldU['loc']?.toString(),
                      oldU['team']?.toString(),
                      oldU['cell']?.toString(),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8.0),
                    child: Icon(Icons.arrow_forward, color: AppPalette.fg(Colors.grey)),
                  ),
                  Expanded(
                    child: _unitInfoBox(
                      "To",
                      newU['loc']?.toString(),
                      newU['team']?.toString(),
                      newU['cell']?.toString(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildActionButtons(req),
            ],
          ),
        );
      },
    );
  }

  Widget _unitInfoBox(String label, String? loc, String? team, String? cell) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppPalette.bg(Colors.grey.shade50),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppPalette.line(Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: AppPalette.fg(pPurple),
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text("Location: ${loc ?? '-'}", style: const TextStyle(fontSize: 12)),
          Text("Team: ${team ?? '-'}", style: const TextStyle(fontSize: 12)),
          Text("Cell: ${cell ?? '-'}", style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}