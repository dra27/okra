(*
 * Copyright (c) 2021 Magnus Skjegstad <magnus@skjegstad.com>
 * Copyright (c) 2021 Thomas Gazagnaire <thomas@gazagnaire.org>
 * Copyright (c) 2021 Patrick Ferris <pf341@patricoferris.com>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *)

let src = Logs.Src.create "okra.KR"

module Log = (val Logs.src_log src : Logs.LOG)

type t = {
  counter : int;
  project : string;
  objective : string;
  title : string;
  id : string option;
  time_entries : (string * float) list list;
  time_per_engineer : (string, float) Hashtbl.t;
  work : Item.t list list;
}

let counter =
  let c = ref 0 in
  fun () ->
    let i = !c in
    incr c;
    i

let v ~project ~objective ~title ~id ~time_entries work =
  let counter = counter () in
  (* Sum time per engineer *)
  let time_per_engineer =
    let tbl = Hashtbl.create 7 in
    List.iter
      (List.iter (fun (e, d) ->
           let d =
             match Hashtbl.find_opt tbl e with None -> d | Some x -> x +. d
           in
           Hashtbl.replace tbl e d))
      time_entries;
    tbl
  in
  {
    counter;
    project;
    objective;
    title;
    id;
    time_entries;
    time_per_engineer;
    work;
  }

let dump =
  let open Fmt.Dump in
  record
    [
      field "counter" (fun t -> t.counter) Fmt.int;
      field "project" (fun t -> t.project) string;
      field "objective" (fun t -> t.objective) string;
      field "title" (fun t -> t.title) string;
      field "id" (fun t -> t.id) (option string);
      field "time_entries"
        (fun t -> t.time_entries)
        (list (list (pair string Fmt.float)));
      field "time_per_engineer"
        (fun t -> List.of_seq (Hashtbl.to_seq t.time_per_engineer))
        (list (pair string Fmt.float));
      field "work" (fun t -> t.work) (list (list Item.dump));
    ]

let compare_no_case x y =
  let x = String.uppercase_ascii x in
  let y = String.uppercase_ascii y in
  String.compare x y

let merge x y =
  let counter = x.counter in
  let title =
    match (x.title, y.title) with
    | "", s | s, "" -> s
    | x, y ->
        if compare_no_case x y <> 0 then
          Log.warn (fun l -> l "Conflicting titles:\n- %S\n- %S" x y);
        x
  in
  let project =
    match (x.project, y.project) with
    | "", s | s, "" -> s
    | x, y ->
        if compare_no_case x y <> 0 then
          Log.warn (fun l ->
              l "KR %S appears in two projects:\n- %S\n- %S" title x y);
        x
  in
  let objective =
    match (x.objective, y.objective) with
    | "", s | s, "" -> s
    | x, y ->
        if compare_no_case x y <> 0 then
          Log.warn (fun l ->
              l "KR %S appears in two objectives:\n- %S\n- %S" title x y);
        x
  in
  let id =
    match (x.id, y.id) with
    | None, None -> None
    | Some x, Some y ->
        assert (compare_no_case x y = 0);
        Some x
    | Some x, _ | _, Some x -> Some x
  in
  let time_entries = x.time_entries @ y.time_entries in
  let time_per_engineer =
    let t = Hashtbl.create 13 in
    Hashtbl.iter (fun k v -> Hashtbl.add t k v) x.time_per_engineer;
    Hashtbl.iter
      (fun k v ->
        match Hashtbl.find_opt t k with
        | None -> Hashtbl.replace t k v
        | Some v' -> Hashtbl.replace t k (v +. v'))
      y.time_per_engineer;
    t
  in
  let work = x.work @ y.work in
  {
    counter;
    project;
    objective;
    title;
    id;
    time_entries;
    time_per_engineer;
    work;
  }

let compare a b =
  match (a.id, b.id) with
  | None, _ | _, None -> compare_no_case a.title b.title
  | Some a, Some b -> compare_no_case a b

let make_days d =
  let d = floor (d *. 2.0) /. 2. in
  if d = 1. then "1 day"
  else if classify_float (fst (modf d)) = FP_zero then
    Printf.sprintf "%.0f days" d
  else Printf.sprintf "%.1f days" d

let make_engineer ~time (e, d) =
  if time then Printf.sprintf "@%s (%s)" e (make_days d)
  else Printf.sprintf "@%s" e

let make_engineers ~time entries =
  let entries = List.of_seq (Hashtbl.to_seq entries) in
  let entries = List.sort (fun (x, _) (y, _) -> String.compare x y) entries in
  let engineers = List.rev_map (make_engineer ~time) entries in
  match engineers with
  | [] -> []
  | e :: es ->
      let open Item in
      let lst =
        List.fold_left
          (fun acc engineer -> Text engineer :: Text ", " :: acc)
          [ Text e ] es
      in
      [ Paragraph (Concat lst) ]

type config = {
  show_engineers : bool;
  show_time : bool;
  show_time_calc : bool;
  include_krs : string list;
}

let id = function None -> "New KR" | Some id -> id

let make_time_entries t =
  let aux (e, d) = Fmt.strf "@%s (%s)" e (make_days d) in
  Item.[ Paragraph (Text (String.concat ", " (List.map aux t))) ]

let items conf kr =
  let open Item in
  if
    conf.include_krs <> []
    &&
    match kr.id with
    | None -> true
    | Some id -> not (List.mem (String.uppercase_ascii id) conf.include_krs)
  then []
  else
    let items =
      if not conf.show_engineers then []
      else if conf.show_time then
        if conf.show_time_calc then
          (* show time calc + engineers *)
          [
            List (Bullet '+', List.map make_time_entries kr.time_entries);
            List (Bullet '=', [ make_engineers ~time:true kr.time_per_engineer ]);
          ]
        else make_engineers ~time:true kr.time_per_engineer
      else make_engineers ~time:false kr.time_per_engineer
    in
    [
      List
        ( Bullet '-',
          [
            [
              Paragraph (Text (Printf.sprintf "%s (%s)" kr.title (id kr.id)));
              List (Bullet '-', items :: kr.work);
            ];
          ] );
    ]