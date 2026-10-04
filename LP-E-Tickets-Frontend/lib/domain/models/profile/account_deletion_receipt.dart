class AccountDeletionReceipt {
  const AccountDeletionReceipt(this.reference, this.state, this.dueAt);

  final String reference;
  final String state;
  final DateTime dueAt;
}
