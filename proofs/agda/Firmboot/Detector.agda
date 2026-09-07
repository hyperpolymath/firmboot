{-# OPTIONS --safe --without-K #-}
module Firmboot.Detector where

open import Firmboot.Prelude

-- Normalized versions of the two known Elixir representations. The absent
-- episode case has no report flag; malformed external states are outside this
-- normalized model and need validation at a future implementation boundary.
data Version : Set where
  v1 v2 : Version

versionEq : (a b : Version) -> Dec (a ≡ b)
versionEq v1 v1 = yes refl
versionEq v2 v2 = yes refl
versionEq v1 v2 = no (λ ())
versionEq v2 v1 = no (λ ())

record Episode : Set where
  constructor episode
  field
    first : Nat
    reported : Bool
open Episode public

record Cursor : Set where
  constructor cursor
  field
    position : Nat
    ongoing : Maybe Episode
open Cursor public

episodeEq : (a b : Episode) -> Dec (a ≡ b)
episodeEq (episode a x) (episode b y) with natEq a b
... | no p = no (λ equality -> p (cong first equality))
... | yes refl with boolEq x y
...   | yes refl = yes refl
...   | no p = no (λ equality -> p (cong reported equality))
ongoingEq : (a b : Maybe Episode) -> Dec (a ≡ b)
ongoingEq nothing nothing = yes refl
ongoingEq nothing (just _) = no (λ ())
ongoingEq (just _) nothing = no (λ ())
ongoingEq (just a) (just b) with episodeEq a b
... | yes refl = yes refl
... | no p = no (λ { refl -> p refl })
cursorEq : (a b : Cursor) -> Dec (a ≡ b)
cursorEq (cursor a x) (cursor b y) with natEq a b
... | no p = no (λ equality -> p (cong position equality))
... | yes refl with ongoingEq x y
...   | yes refl = yes refl
...   | no p = no (λ equality -> p (cong ongoing equality))

countFrom : Cursor -> Nat
countFrom (cursor p nothing) = 0
countFrom (cursor p (just e)) = p - first e + 1

data Representation : Set where
  V1 : Cursor -> Nat -> Representation
  V2 : Cursor -> List Bool -> Representation

owner : Representation -> Version
owner (V1 _ _) = v1
owner (V2 _ _) = v2
viewCursor : Representation -> Cursor
viewCursor (V1 c _) = c
viewCursor (V2 c _) = c

build : Version -> Cursor -> List Bool -> Representation
build v1 c _ = V1 c (countFrom c)
build v2 c w = V2 c w

buildCursor : (v : Version) (c : Cursor) (w : List Bool) -> viewCursor (build v c w) ≡ c
buildCursor v1 c w = refl
buildCursor v2 c w = refl
buildOwner : (v : Version) (c : Cursor) (w : List Bool) -> owner (build v c w) ≡ v
buildOwner v1 c w = refl
buildOwner v2 c w = refl

countField : Representation -> Nat
countField (V1 _ n) = n
countField (V2 _ _) = 0
windowField : Representation -> List Bool
windowField (V1 _ _) = []
windowField (V2 _ w) = w

representationEq : (a b : Representation) -> Dec (a ≡ b)
representationEq (V1 c n) (V1 d m) with cursorEq c d
... | no p = no (λ equality -> p (cong viewCursor equality))
... | yes refl with natEq n m
...   | yes refl = yes refl
...   | no p = no (λ equality -> p (cong countField equality))
representationEq (V2 c w) (V2 d z) with cursorEq c d
... | no p = no (λ equality -> p (cong viewCursor equality))
... | yes refl with listEq boolEq w z
...   | yes refl = yes refl
...   | no p = no (λ equality -> p (cong windowField equality))
representationEq (V1 _ _) (V2 _ _) = no (λ ())
representationEq (V2 _ _) (V1 _ _) = no (λ ())

record Frame : Set where
  constructor frame
  field
    sequence : Nat
    value : Bool
    processedBy : Version
open Frame public

record Event : Set where
  constructor event
  field
    episodeID : Nat
    detectedAt : Nat
    emittedBy : Version

record Boundary : Set where
  constructor boundary
  field
    detector : Representation
    history : List Bool
    frames : List Frame
    events : List Event
open Boundary public

currentCursor : Boundary -> Cursor
currentCursor b = viewCursor (detector b)
currentOwner : Boundary -> Version
currentOwner b = owner (detector b)

initial : Boundary
initial = boundary (V1 (cursor 0 nothing) 0) [] [] []

requiredHistory : Version -> Nat
requiredHistory v1 = 0
requiredHistory v2 = three

eligible : Version -> Nat -> Nat -> List Bool -> Bool
eligible v1 pos first _ = isYes (≤? 2 (pos - first + 1))
eligible v2 _ _ w = isYes (listEq boolEq w (true ∷ true ∷ true ∷ []))

-- One sample decides whether the ongoing episode first becomes reported.
record Decision : Set where
  constructor decision
  field
    nextEpisode : Maybe Episode
    newEvent : Maybe Event
open Decision public

high : Version -> Nat -> Episode -> List Bool -> Decision
high v seq (episode first true) w = decision (just (episode first true)) nothing
high v seq (episode first false) w with eligible v seq first w
... | false = decision (just (episode first false)) nothing
... | true = decision (just (episode first true)) (just (event first seq v))

decideSample : Version -> Cursor -> List Bool -> Bool -> Decision
decideSample v c w false = decision nothing nothing
decideSample v (cursor p nothing) w true = high v (suc p) (episode (suc p) false) w
decideSample v (cursor p (just e)) w true = high v (suc p) e w

recordEvent : Maybe Event -> List Event -> List Event
recordEvent nothing es = es
recordEvent (just e) es = e ∷ es

process : Boundary -> Bool -> Boundary
process b input = boundary
  (build (currentOwner b) nextCursor window)
  newHistory
  (frame (suc (position (currentCursor b))) input (currentOwner b) ∷ frames b)
  (recordEvent (newEvent choice) (events b))
  where
    newHistory = history b ++ (input ∷ [])
    window = recent newHistory
    choice = decideSample (currentOwner b) (currentCursor b) window input
    nextCursor = cursor (suc (position (currentCursor b))) (nextEpisode choice)

processOwner : (b : Boundary) (input : Bool) -> currentOwner (process b input) ≡ currentOwner b
processOwner b input = buildOwner _ _ _
processPosition : (b : Boundary) (input : Bool) ->
  position (currentCursor (process b input)) ≡ suc (position (currentCursor b))
processPosition b input = cong position (buildCursor (currentOwner b)
  (cursor (suc (position (currentCursor b)))
    (nextEpisode (decideSample (currentOwner b) (currentCursor b)
      (recent (history b ++ (input ∷ []))) input)))
  (recent (history b ++ (input ∷ []))))
processFrames : (b : Boundary) (input : Bool) -> frames (process b input) ≡
  frame (suc (position (currentCursor b))) input (currentOwner b) ∷ frames b
processFrames b input = refl
