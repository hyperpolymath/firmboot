{-# OPTIONS --safe --without-K #-}
module Firmboot.Prelude where

open import Agda.Builtin.Bool public using (Bool; true; false)
open import Agda.Builtin.Equality public using (_≡_; refl)
open import Agda.Builtin.Nat public using (Nat; zero; suc; _+_; _-_)
open import Agda.Builtin.List public using (List; []; _∷_)
open import Agda.Builtin.Maybe public using (Maybe; nothing; just)
open import Agda.Builtin.Sigma public using (Σ; _,_; fst; snd)
open import Agda.Builtin.Unit public using (⊤; tt)

infixr 5 _++_
infix 4 _≤_

data ⊥ : Set where
¬_ : Set -> Set
¬ A = A -> ⊥

data Dec (A : Set) : Set where
  yes : A -> Dec A
  no : ¬ A -> Dec A

sym : {A : Set} {x y : A} -> x ≡ y -> y ≡ x
sym refl = refl
trans : {A : Set} {x y z : A} -> x ≡ y -> y ≡ z -> x ≡ z
trans refl q = q
cong : {A B : Set} {x y : A} -> (f : A -> B) -> x ≡ y -> f x ≡ f y
cong f refl = refl
cong₂ : {A B C : Set} (f : A -> B -> C) {a a' : A} {b b' : B} ->
  a ≡ a' -> b ≡ b' -> f a b ≡ f a' b'
cong₂ f refl refl = refl
subst : {A : Set} (P : A -> Set) {x y : A} -> x ≡ y -> P x -> P y
subst P refl p = p

_++_ : {A : Set} -> List A -> List A -> List A
[] ++ ys = ys
(x ∷ xs) ++ ys = x ∷ (xs ++ ys)
appendAssoc : {A : Set} (xs ys zs : List A) -> (xs ++ ys) ++ zs ≡ xs ++ (ys ++ zs)
appendAssoc [] ys zs = refl
appendAssoc (x ∷ xs) ys zs = cong (λ rest -> x ∷ rest) (appendAssoc xs ys zs)
length : {A : Set} -> List A -> Nat
length [] = zero
length (_ ∷ xs) = suc (length xs)
map : {A B : Set} -> (A -> B) -> List A -> List B
map f [] = []
map f (x ∷ xs) = f x ∷ map f xs

data _≤_ : Nat -> Nat -> Set where
  z≤ : {n : Nat} -> zero ≤ n
  s≤ : {m n : Nat} -> m ≤ n -> suc m ≤ suc n

≤? : (m n : Nat) -> Dec (m ≤ n)
≤? zero _ = yes z≤
≤? (suc _) zero = no (λ ())
≤? (suc m) (suc n) with ≤? m n
... | yes p = yes (s≤ p)
... | no p = no (λ { (s≤ q) -> p q })

natEq : (m n : Nat) -> Dec (m ≡ n)
natEq zero zero = yes refl
natEq zero (suc _) = no (λ ())
natEq (suc _) zero = no (λ ())
natEq (suc m) (suc n) with natEq m n
... | yes refl = yes refl
... | no p = no (λ { refl -> p refl })
boolEq : (a b : Bool) -> Dec (a ≡ b)
boolEq true true = yes refl
boolEq false false = yes refl
boolEq true false = no (λ ())
boolEq false true = no (λ ())

consHeadEq : {A : Set} {x y : A} {xs ys : List A} -> x ∷ xs ≡ y ∷ ys -> x ≡ y
consHeadEq refl = refl
consTailEq : {A : Set} {x y : A} {xs ys : List A} -> x ∷ xs ≡ y ∷ ys -> xs ≡ ys
consTailEq refl = refl

listEq : {A : Set} -> ((a b : A) -> Dec (a ≡ b)) -> (xs ys : List A) -> Dec (xs ≡ ys)
listEq eq [] [] = yes refl
listEq eq [] (_ ∷ _) = no (λ ())
listEq eq (_ ∷ _) [] = no (λ ())
listEq eq (x ∷ xs) (y ∷ ys) with eq x y
... | no p = no (λ equality -> p (consHeadEq equality))
... | yes refl with listEq eq xs ys
...   | yes refl = yes refl
...   | no p = no (λ equality -> p (consTailEq equality))

isYes : {A : Set} -> Dec A -> Bool
isYes (yes _) = true
isYes (no _) = false

three : Nat
three = 3

-- Chronological suffix of at most three observations.
recent : {A : Set} -> List A -> List A
recent [] = []
recent (a ∷ []) = a ∷ []
recent (a ∷ b ∷ []) = a ∷ b ∷ []
recent (a ∷ b ∷ c ∷ []) = a ∷ b ∷ c ∷ []
recent (a ∷ b ∷ c ∷ d ∷ rest) = recent (b ∷ c ∷ d ∷ rest)

recentBound : {A : Set} (xs : List A) -> length (recent xs) ≤ three
recentBound [] = z≤
recentBound (a ∷ []) = s≤ z≤
recentBound (a ∷ b ∷ []) = s≤ (s≤ z≤)
recentBound (a ∷ b ∷ c ∷ []) = s≤ (s≤ (s≤ z≤))
recentBound (a ∷ b ∷ c ∷ d ∷ rest) = recentBound (b ∷ c ∷ d ∷ rest)
