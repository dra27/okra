(*
 * Copyright (c) 2021 Magnus Skjegstad <magnus@skjegstad.com>
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

let aggregate f =
  let ic = open_in f in
  let omd = Omd.of_channel ic in
  let p = Okra.Report.of_markdown omd in
  close_in ic;
  p

let contains_kr_cnt p kr_id =
  let found = ref 0 in
  Okra.Report.iter
    (fun kr -> if kr.kind = kr_id then found := !found + 1 else ())
    p;
  !found

let contains_kr p kr_id = contains_kr_cnt p kr_id > 0

let test_newkr_replaced1 () =
  let res = aggregate "./reports/newkr_replaced1.acc" in
  Alcotest.(check bool) "new KR replaced" true (not (contains_kr res `New));
  Alcotest.(check int) "KR123 exists once" 1 (contains_kr_cnt res (`Id "KR123"));
  Alcotest.(check int) "KR124 exists once" 1 (contains_kr_cnt res (`Id "KR124"));
  Alcotest.(check int) "KR125 exists once" 1 (contains_kr_cnt res (`Id "KR125"))

let test_newkr_exists1 () =
  let res = aggregate "./reports/newkr_exists1.acc" in
  Alcotest.(check bool) "new KR exists" true (contains_kr res `New);
  let res = Okra.Aggregate.by_engineer res in
  Alcotest.(check (float 0.0)) "eng1 time" 1.0 (Hashtbl.find res "eng1")

let test_kr_agg1 () =
  let res = aggregate "./reports/kr_agg1.acc" in
  Alcotest.(check bool) "KR123 exists" true (contains_kr res (`Id "KR123"));
  Alcotest.(check int)
    "KR123 aggregated into one item" 1
    (contains_kr_cnt res (`Id "KR123"));
  let res = Okra.Aggregate.by_engineer res in
  (* also check that time adds up *)
  Alcotest.(check (float 0.0)) "eng1 time" 4.0 (Hashtbl.find res "eng1")

let tests =
  [
    ("Test_kr_aggregation", `Quick, test_kr_agg1);
    ("Test_newkr_exists", `Quick, test_newkr_exists1);
    ("Test_newkr_replaced", `Quick, test_newkr_replaced1);
  ]
