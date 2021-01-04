(*
 * Copyright (c) Facebook, Inc. and its affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

open Core
open Pyre
open Ast

module T = struct
  type incompatible_model_error_reason =
    | UnexpectedPositionalOnlyParameter of string
    | UnexpectedNamedParameter of string
    | UnexpectedStarredParameter
    | UnexpectedDoubleStarredParameter
  [@@deriving eq, show]

  type kind =
    | InvalidDefaultValue of {
        callable_name: string;
        name: string;
        expression: Expression.t;
      }
    | IncompatibleModelError of {
        name: string;
        callable_type: Type.Callable.t;
        reasons: incompatible_model_error_reason list;
      }
    | ImportedFunctionModel of {
        name: Reference.t;
        actual_name: Reference.t;
      }
    | InvalidModelQueryClauses of Expression.Call.Argument.t list
    | MissingAttribute of {
        class_name: string;
        attribute_name: string;
      }
    | NotInEnvironment of string
    | UnexpectedDecorators of {
        name: Reference.t;
        unexpected_decorators: Statement.Decorator.t list;
      }
    (* TODO(T81363867): Remove this variant. *)
    | UnclassifiedError of {
        model_name: string;
        message: string;
      }
  [@@deriving eq, show]

  type t = {
    kind: kind;
    path: Path.t option;
    location: Location.t;
  }
  [@@deriving eq, show]
end

include T

let description error =
  match error with
  | InvalidDefaultValue { callable_name; name; expression } ->
      Format.sprintf
        "Default values of `%s`'s parameters must be `...`. Did you mean to write `%s: %s`?"
        callable_name
        name
        (Expression.show expression)
  | IncompatibleModelError { name; callable_type; reasons } ->
      let reasons =
        List.map reasons ~f:(function
            | UnexpectedPositionalOnlyParameter name ->
                Format.sprintf "unexpected positional only parameter: `%s`" name
            | UnexpectedNamedParameter name ->
                Format.sprintf "unexpected named parameter: `%s`" name
            | UnexpectedStarredParameter -> "unexpected star parameter"
            | UnexpectedDoubleStarredParameter -> "unexpected star star parameter")
      in
      Format.asprintf
        "Model signature parameters for `%s` do not match implementation `%s`. Reason%s: %s."
        name
        (Type.show_for_hover (Type.Callable callable_type))
        (if List.length reasons > 1 then "s" else "")
        (String.concat reasons ~sep:"; ")
  | ImportedFunctionModel { name; actual_name } ->
      Format.asprintf
        "The modelled function `%a` is an imported function, please model `%a` directly."
        Reference.pp
        name
        Reference.pp
        actual_name
  | InvalidModelQueryClauses clause_list ->
      Format.asprintf
        "The model query arguments at `%s` are invalid: expected a find, where and model clause."
        (List.map clause_list ~f:Expression.Call.Argument.show |> String.concat ~sep:", ")
  | UnexpectedDecorators { name; unexpected_decorators } ->
      let decorators =
        List.map unexpected_decorators ~f:Statement.Decorator.to_expression
        |> List.map ~f:Expression.show
      in
      let property_decorator_message =
        if List.exists decorators ~f:(String.is_substring ~substring:"property") then
          " If you're looking to model a custom property decorator, use the @property decorator."
        else
          ""
      in
      Format.asprintf
        "Unexpected decorators found when parsing model for `%a`: `%s`.%s"
        Reference.pp
        name
        (String.concat decorators ~sep:", ")
        property_decorator_message
  | UnclassifiedError { model_name; message } ->
      Format.sprintf "Invalid model for `%s`: %s" model_name message
  | MissingAttribute { class_name; attribute_name } ->
      Format.sprintf "Class `%s` has no attribute `%s`." class_name attribute_name
  | NotInEnvironment name -> Format.sprintf "`%s` is not part of the environment!" name


let display { kind = error; path; location } =
  let model_origin =
    match path with
    | None -> ""
    | Some path -> Format.sprintf "%s:%d: " (Path.absolute path) Location.(location.start.line)
  in
  Format.sprintf "%s%s" model_origin (description error)


let to_json { kind; path; location } =
  let path =
    match path with
    | None -> `Null
    | Some path -> `String (Path.absolute path)
  in
  `Assoc
    [
      "description", `String (description kind);
      "line", `Int Location.(location.start.line);
      "column", `Int Location.(location.start.column);
      "path", path;
    ]
