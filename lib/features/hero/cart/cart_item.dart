class CartItem {
  final String name;
  final String condition;
  final int quantity;

  const CartItem({
    required this.name,
    required this.condition,
    this.quantity = 1,
  });

  CartItem copyWith({int? quantity}) {
    return CartItem(
      name: name,
      condition: condition,
      quantity: quantity ?? this.quantity,
    );
  }
}
