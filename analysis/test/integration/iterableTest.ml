(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open OUnit2
open IntegrationTest

let test_check_contains context =
  let assert_type_errors = assert_type_errors ~context in
  assert_type_errors
    {|
        class Container:
            def __getitem__(self, item: str) -> None:
                pass

        def foo(x: str) -> None:
            if x in Container():
                pass
    |}
    [];

  assert_type_errors
    {|
        class NonContainer:
            pass

        def foo(x: str) -> None:
            if x in NonContainer():
                pass
    |}
    ["Undefined attribute [16]: `NonContainer` has no attribute `__getitem__`."];
  ()


let () = "iterable" >::: ["check_contains" >:: test_check_contains] |> Test.run