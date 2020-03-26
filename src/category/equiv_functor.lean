/-
Copyright (c) 2020 Scott Morrison. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Scott Morrison
-/

import category_theory.category
import data.equiv.functor

/-!
# Functions functorial with respect to equivalences

An `equiv_functor` is a function from `Type → Type` equipped with the additional data of
coherently mapping equivalences to equivalences.

In categorical language, it is an endofunctor of the "core" of the category `Type`.
-/

universes u₀ u₁ u₂ v₀ v₁ v₂

open function

/--
An `equiv_functor` is only functorial with respect to equivalences.

To construct an `equiv_functor`, it suffices to supply just the function `f α → f β` from
an equivalence `α ≃ β`, and then prove the functor laws. It's then a consequence that
this function is part of an equivalence, provided by `equiv_functor.map_equiv`.
-/
class equiv_functor (f : Type u₀ → Type u₁) :=
(map : Π {α β}, (α ≃ β) → (f α → f β))
(id_map' : Π α, map (equiv.refl α) = @id (f α) . obviously)
(map_map' : Π {α β γ} (k : α ≃ β) (h : β ≃ γ),
  map (k.trans h) = (map h) ∘ (map k) . obviously)

restate_axiom equiv_functor.id_map'
restate_axiom equiv_functor.map_map'
attribute [simp] equiv_functor.id_map

namespace equiv_functor

section
variables (f : Type u₀ → Type u₁) [equiv_functor f] {α β : Type u₀} (e : α ≃ β)

/-- An `equiv_functor` in fact takes every equiv to an equiv. -/
def map_equiv :
  f α ≃ f β :=
{ to_fun := equiv_functor.map e,
  inv_fun := equiv_functor.map e.symm,
  left_inv := λ x, begin convert (congr_fun (equiv_functor.map_map f e e.symm) x).symm, simp, end,
  right_inv := λ y, begin convert (congr_fun (equiv_functor.map_map f e.symm e) y).symm, simp, end, }

@[simp] lemma map_equiv_apply (x : f α) :
  map_equiv f e x = equiv_functor.map e x := rfl

@[simp] lemma map_equiv_symm_apply (y : f β) :
  (map_equiv f e).symm y = equiv_functor.map e.symm y := rfl
end

@[priority 100]
instance of_is_lawful_functor
  (f : Type u₀ → Type u₁) [functor f] [is_lawful_functor f] : equiv_functor f :=
{ map := λ α β e, functor.map e,
  id_map' := λ α, by { ext, apply is_lawful_functor.id_map, },
  map_map' := λ α β γ k h, by { ext x, apply (is_lawful_functor.comp_map k h x), } }

-- TODO Include more examples here;
-- once `equiv_rw` is available these are easy to construct,
-- and in turn make `equiv_rw` more powerful.
instance equiv_functor_unique : equiv_functor unique :=
{ map := λ α β e, equiv.unique_congr e, }

end equiv_functor
