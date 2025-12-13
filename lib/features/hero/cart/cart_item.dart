class CartItem {
  final String name;
  final String condition;
  final int quantity;
  final double price;
  final double weight;

  const CartItem({
    required this.name,
    required this.condition,
    this.quantity = 1,
    required this.price,
    this.weight = 0.5,
  });

  CartItem copyWith({int? quantity}) {
    return CartItem(
      name: name,
      condition: condition,
      quantity: quantity ?? this.quantity,
      price: price,
      weight: weight,
    );
  }
}
