from .mobile import (
    MobileCommonMixin,
    MobileCatalogMixin,
    MobileWalletMixin,
    MobilePurchasesMixin,
    MobileTransactionsMixin,
    MobileTicketsMixin,
    MobileQrMixin,
    MobileTransfersMixin,
)


class AcpecFuelTokenMobileApi(
    MobileCommonMixin,
    MobileCatalogMixin,
    MobileWalletMixin,
    MobilePurchasesMixin,
    MobileTransactionsMixin,
    MobileTicketsMixin,
    MobileQrMixin,
    MobileTransfersMixin,
):
    """Compatibility controller combining mobile API endpoints by feature."""

    # Keep the routed methods in this controller class so Odoo discovers the
    # existing routes while their implementations live in feature modules.
    carnet_types = MobileCatalogMixin.carnet_types
    payment_methods = MobileCatalogMixin.payment_methods
    mobile_stations_list = MobileCatalogMixin.mobile_stations_list
    current_wallet = MobileWalletMixin.current_wallet
    update_wallet_qr_limit = MobileWalletMixin.update_wallet_qr_limit
    create_purchase = MobilePurchasesMixin.create_purchase
    purchases = MobilePurchasesMixin.purchases
    purchase_detail = MobilePurchasesMixin.purchase_detail
    transactions = MobileTransactionsMixin.transactions
    transaction_detail = MobileTransactionsMixin.transaction_detail
    faces = MobileTicketsMixin.faces
    issue_qr = MobileQrMixin.issue_qr
    qr_list = MobileQrMixin.qr_list
    qr_detail = MobileQrMixin.qr_detail
    qr_reveal_code = MobileQrMixin.qr_reveal_code
    retirer_qr = MobileQrMixin.retirer_qr
    separer_qr = MobileQrMixin.separer_qr
    transfer_tickets = MobileTransfersMixin.transfer_tickets
    transfer_carnets_recipient = MobileTransfersMixin.transfer_carnets_recipient
    transfer_carnets = MobileTransfersMixin.transfer_carnets
    transfer_list = MobileTransfersMixin.transfer_list
