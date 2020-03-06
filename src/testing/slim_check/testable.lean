
import testing.slim_check.arbitrary

universes u v

variable α : Type u
variable β : α → Prop
variable f : Type → Prop

namespace slim_check

/-- Result of trying to disprove `p` -/
@[derive inhabited]
inductive test_result (p : Prop)
  /- succeed when we find another example satifying `p` -/
| success : (psum unit p) → test_result
  /- give up when a well-formed example cannot be generated -/
| gave_up {} : ℕ → test_result
  /- a counter-example to `p`; the strings specify values for the relevant variables -/
| failure : ¬ p → (list string) → test_result

/-- `testable p` uses random examples to try to disprove `p` -/
class testable (p : Prop) :=
(run (minimize : bool) : gen (test_result p)) --

open list

open test_result

/-- applicative combinator proof carrying test results -/
def combine {p q : Prop} : psum unit (p → q) → psum unit p → psum unit q
| (psum.inr f) (psum.inr x) := psum.inr (f x)
| _ _ := psum.inl ()

/-- If `q → p`, then `¬ p → ¬ q` which means that testing `p` can allow us
to find counter-examples to `q` -/
def convert_counter_example {p q : Prop}
  (h : q → p) :
  test_result p →
  opt_param (psum unit (p → q)) (psum.inl ()) →
  test_result q
 | (failure Hce xs) _ := failure (mt h Hce) xs
 | (success Hp) Hpq := success (combine Hpq Hp)
 | (gave_up n) _ := gave_up n

/-- When we assign a value to a universally quantified variable,
we record that value using this function so that our counter-examples
can be informative -/
def add_to_counter_example (x : string) {p q : Prop}
  (h : q → p)
: test_result p →
  opt_param (psum unit (p → q)) (psum.inl ()) →
  test_result q
 | (failure Hce xs) _ := failure (mt h Hce) $ x :: xs
 | r hpq := convert_counter_example h r hpq

/-- add some formatting to the information recorded by `add_to_counter_example` -/
def add_var_to_counter_example {γ : Type v} [has_to_string γ]
  (var : string) (x : γ) {p q : Prop}
  (h : q → p)
: test_result p →
  opt_param (psum unit (p → q)) (psum.inl ()) →
  test_result q :=
@add_to_counter_example (var ++ " := " ++ to_string x) _ _ h

instance imp_dec_testable (p : Prop) [decidable p] (β : p → Prop)
  [∀ h, testable (β h)]
: testable (Π h, β h) :=
⟨ λ min, do
    if h : p
    then (λ r, convert_counter_example ($ h) r (psum.inr $ λ q _, q)) <$> testable.run (β h) min
    else return $ gave_up 1 ⟩

instance all_types_testable [testable (f ℤ)]
: testable (Π x, f x) :=
⟨ λ min, do
    r ← testable.run (f ℤ) min,
    return $ add_to_counter_example "ℤ" ($ ℤ) r ⟩

/-- testable instance for universal properties; use the chosen example and
instantiate the universal quantification with it -/
def test_one (x : α) [testable (β x)] (var : option (string × string) := none) : testable (Π x, β x) :=
⟨ λ min, do
    r ← testable.run (β x) min,
    return $ match var with
      | none := convert_counter_example ($ x) r
      | (some (v,x_str)) := add_var_to_counter_example v x_str ($ x) r
      end ⟩

/-- testable instance for a property iterating over the element of a list -/
def test_forall_in_list (var : string) [∀ x, testable (β x)] [has_to_string α] :
  Π xs : list α, testable (∀ x, x ∈ xs → β x)
| [] := ⟨ λ min, return $ success $ psum.inr (by { introv h, cases h} ) ⟩
| (x :: xs) :=
⟨ λ min, do
    r ← testable.run (β x) min,
    match r with
     | failure _ _ := return $ add_var_to_counter_example var x
                               (by { intro h, apply h, left, refl }) r
     | success hp := do
       rs ← @testable.run _ (test_forall_in_list xs) min,
       return $ convert_counter_example
                               (by { intros h i h',
                                     apply h,
                                     right, apply h' })
                               rs
                               (combine (psum.inr
                                $ by { intros j h, simp only [ball_cons],
                                       split ; assumption, } ) hp)
     | gave_up n := do
       rs ← @testable.run _ (test_forall_in_list xs) min,
       match rs with
        | (success _) := return $ gave_up n
        | (failure Hce xs) := return $ failure
                    (by { simp only [ball_cons],
                          apply not_and_of_not_right _ Hce, }) xs
        | (gave_up n') := return $ gave_up (n + n')
       end
    end ⟩

/-- Test proposition `p` by randomly selecting one of the provided
testable instance -/
def combine_testable (p : Prop)
  (t : list $ testable p) (h : 0 < t.length)
: testable p :=
⟨ λ min, have 0 < length (map (λ t, @testable.run _ t min) t),
    by { rw [length_map], apply h },
  one_of (list.map (λ t, @testable.run _ t min) t) this ⟩

/-- Is the given test result a failure? -/
def is_failure {p} : test_result p → bool
| (test_result.failure _ _) := tt
| _ := ff

/-- Once a property fails to hold on an example, look for smaller counter-examples
to show the user -/
def minimize [∀ x, testable (β x)] (x : α) (r : test_result (β x)) : lazy_list α → gen (Σ x, test_result (β x))
| lazy_list.nil := pure ⟨x,r⟩
| (lazy_list.cons x xs) := do
  ⟨r⟩ ← liftable.up' $ testable.run (β x) tt,
     if is_failure r
       then pure ⟨x, convert_counter_example id r (psum.inl ())⟩
       else minimize $ xs ()

/-- Test a universal property by choosing arbitrary examples to instantiate the
bound variable with -/
def var_testable [has_to_string α] [arbitrary α] [∀ x, testable (β x)]
  (var : option string := none)
: testable (Π x : α, β x) :=
⟨ λ min, liftable.down' $ do
  x ← arby α,
  (do
    ⟨r⟩ ← liftable.up' $ testable.run (β x) ff,
    ⟨x,r⟩ ← if is_failure r ∧ min then minimize _ _ x r (shrink x) else pure ⟨x,r⟩,
    return ⟨match var with
     | none := add_to_counter_example (to_string x) ($ x) r
     | (some v) := add_var_to_counter_example v x ($ x) r
    end⟩) ⟩

instance pi_testable [has_to_string α] [arbitrary α] [∀ x, testable (β x)]
: testable (Π x : α, β x) :=
var_testable α β

@[priority 100]
instance de_testable {p : Prop} [decidable p] : testable p :=
⟨ λ min, return $ if h : p then success (psum.inr h) else failure h [] ⟩

section io

variable (p : Prop)

open nat

variable {p}

/-- execute `cmd` and repeat every time the result is `gave_up` or at most
`n` times -/
def retry (cmd : rand (test_result p)) : ℕ → rand (test_result p)
 | 0 := return $ gave_up 1
 | (succ n) := do
r ← cmd,
match r with
 | success hp := return $ success hp
 | (failure Hce xs) := return (failure Hce xs)
 | (gave_up _) := retry n
end

/-- Count the number of time the test procedure gave up -/
def give_up (x : ℕ) : test_result p → test_result p
 | (success (psum.inl ())) := gave_up x
 | (success (psum.inr p))  := success (psum.inr p)
 | (gave_up n) := gave_up (n+x)
 | (failure Hce xs) := failure Hce xs

variable (p)

variable [testable p]

/-- Try `n` times to find a counter-example for `p` -/
def testable.run_suite_aux (bound : ℕ) : test_result p → ℕ → rand (test_result p)
 | r 0 := return r
 | r (succ n) :=
do x ← retry ( (testable.run p tt).run ⟨ (bound - n - 1) ⟩) 10,
   match x with
    | (success (psum.inl ())) := testable.run_suite_aux r n
    | (success (psum.inr Hp)) := return $ success (psum.inr Hp)
    | (failure Hce xs) := return (failure Hce xs)
    | (gave_up g) := testable.run_suite_aux (give_up g r) n
   end

/-- Try to find a counter-example of `p` -/
def testable.run_suite (bound : ℕ := 100) : rand (test_result p) :=
testable.run_suite_aux p bound (success $ psum.inl ()) (2*bound)

/-- Run a test suite for `p` in `io` -/
def testable.check (bound : ℕ := 100) : io (test_result p) :=
io.run_rand (testable.run_suite p bound)

/-- Run a test suite for `p` and return true or false: should we believe that `p` holds? -/
def testable.check' (bound : ℕ := 100) : io bool := do
x ← io.run_rand (testable.run_suite p bound),
match x with
 | (success _) := return tt
 | (gave_up n) := io.put_str_ln ("Gave up " ++ repr n ++ " times") >> return ff
 | (failure _ xs) := do
   io.put_str_ln "\n===================",
   io.put_str_ln "Found problems!",
   io.put_str_ln "",
   list.mmap' io.put_str_ln xs,
   io.put_str_ln "-------------------",
   return ff
end

end io

end slim_check