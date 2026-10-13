package com.redhat.coolstore.rest;

import java.io.Serializable;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.logging.Logger;

import javax.enterprise.context.SessionScoped;
import javax.inject.Inject;
import javax.ws.rs.DELETE;
import javax.ws.rs.GET;
import javax.ws.rs.POST;
import javax.ws.rs.Path;
import javax.ws.rs.PathParam;
import javax.ws.rs.Produces;
import javax.ws.rs.WebApplicationException;
import javax.ws.rs.core.MediaType;
import javax.ws.rs.core.Response;

import com.redhat.coolstore.model.Product;
import com.redhat.coolstore.model.ShoppingCart;
import com.redhat.coolstore.model.ShoppingCartItem;
import com.redhat.coolstore.service.ShoppingCartService;

@SessionScoped
@Path("/cart")
public class CartEndpoint implements Serializable {

	private static final long serialVersionUID = -7227732980791688773L;

	@Inject
	Logger log;

	@Inject
	private ShoppingCartService shoppingCartService;

	@GET
	@Path("/{cartId}")
	@Produces(MediaType.APPLICATION_JSON)
	public ShoppingCart getCart(@PathParam("cartId") String cartId) {
		return shoppingCartService.getShoppingCart(cartId);
	}

	@POST
	@Path("/checkout/{cartId}")
	@Produces(MediaType.APPLICATION_JSON)
	public ShoppingCart checkout(@PathParam("cartId") String cartId) {
		return shoppingCartService.checkOutShoppingCart(cartId);
	}

	@POST
	@Path("/{cartId}/{itemId}/{quantity}")
	@Produces(MediaType.APPLICATION_JSON)
	public ShoppingCart add(@PathParam("cartId") String cartId,
							@PathParam("itemId") String itemId,
							@PathParam("quantity") int quantity) {
		ShoppingCart cart = shoppingCartService.getShoppingCart(cartId);

		Product product = shoppingCartService.getProduct(itemId);
		if (product == null) {
			throw new WebApplicationException("Product not found: " + itemId, Response.Status.NOT_FOUND);
		}

		ShoppingCartItem sci = new ShoppingCartItem();
		sci.setProduct(product);
		sci.setQuantity(quantity);
		sci.setPrice(product.getPrice());
		cart.addShoppingCartItem(sci);

		try {
			shoppingCartService.priceShoppingCart(cart);
			cart.setShoppingCartItemList(dedupeCartItems(cart.getShoppingCartItemList()));
		} catch (RuntimeException ex) {
			log.warning("Failed to price cart " + cartId + ", rolling back item addition: " + ex.getMessage());
			cart.removeShoppingCartItem(sci);
			throw new WebApplicationException("Failed to price cart", ex, Response.Status.INTERNAL_SERVER_ERROR);
		}

		return cart;
	}

	@POST
	@Path("/{cartId}/{tmpId}")
	@Produces(MediaType.APPLICATION_JSON)
	public ShoppingCart set(@PathParam("cartId") String cartId,
							@PathParam("tmpId") String tmpId) {

		ShoppingCart cart = shoppingCartService.getShoppingCart(cartId);
		ShoppingCart tmpCart = shoppingCartService.getShoppingCart(tmpId);

		if (tmpCart != null) {
			cart.resetShoppingCartItemList();
			cart.setShoppingCartItemList(tmpCart.getShoppingCartItemList());
		}

		try {
			shoppingCartService.priceShoppingCart(cart);
			cart.setShoppingCartItemList(dedupeCartItems(cart.getShoppingCartItemList()));
		} catch (RuntimeException ex) {
			log.warning("Failed to price cart " + cartId + ": " + ex.getMessage());
			throw new WebApplicationException("Failed to price cart", ex, Response.Status.INTERNAL_SERVER_ERROR);
		}

		return cart;
	}

	@DELETE
	@Path("/{cartId}/{itemId}/{quantity}")
	@Produces(MediaType.APPLICATION_JSON)
	public ShoppingCart delete(@PathParam("cartId") String cartId,
							   @PathParam("itemId") String itemId,
							   @PathParam("quantity") int quantity) {

		List<ShoppingCartItem> toRemoveList = new ArrayList<>();

		ShoppingCart cart = shoppingCartService.getShoppingCart(cartId);

		cart.getShoppingCartItemList().stream()
				.filter(sci -> sci.getProduct().getItemId().equals(itemId))
				.forEach(sci -> {
					if (quantity >= sci.getQuantity()) {
						toRemoveList.add(sci);
					} else {
						sci.setQuantity(sci.getQuantity() - quantity);
					}
				});

		toRemoveList.forEach(cart::removeShoppingCartItem);

		shoppingCartService.priceShoppingCart(cart);
		return cart;
	}



	private List<ShoppingCartItem> dedupeCartItems(List<ShoppingCartItem> cartItems) {
		List<ShoppingCartItem> result = new ArrayList<>();
		Map<String, Integer> quantityMap = new HashMap<>();
		for (ShoppingCartItem sci : cartItems) {
			if (quantityMap.containsKey(sci.getProduct().getItemId())) {
				quantityMap.put(sci.getProduct().getItemId(), quantityMap.get(sci.getProduct().getItemId()) + sci.getQuantity());
			} else {
				quantityMap.put(sci.getProduct().getItemId(), sci.getQuantity());
			}
		}

		for (String itemId : quantityMap.keySet()) {
			Product p = shoppingCartService.getProduct(itemId);
			ShoppingCartItem newItem = new ShoppingCartItem();
			newItem.setQuantity(quantityMap.get(itemId));
			newItem.setPrice(p.getPrice());
			newItem.setProduct(p);
			result.add(newItem);
		}
		return result;
	}
}
