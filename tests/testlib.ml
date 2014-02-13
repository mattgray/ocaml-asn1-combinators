
open OUnit2
open Bigarray


type testcase =
  | TC : string * 'a Asn.t * ('a * int list) list -> testcase

let case
: type a. string -> a Asn.t -> (a * int list) list -> testcase
= fun name asn examples -> TC (name, asn, examples)


let assert_decode
: type a. a Asn.codec -> Asn.bytes -> a -> unit
= fun codec bytes a ->
  match Asn.decode codec bytes with
  | None -> assert_failure "decode failed"
  | Some (x, buf) ->
      if Array1.dim buf <> 0 then
        assert_failure "not all input consumed"
      else assert_equal a x

let test_decode (TC (_, asn, examples)) _ =
  let codec = Asn.(codec ber asn) in
  examples |> List.iter @@ fun (a, bytes) ->
    let arr = Dumpkit.bytes_of_list bytes in
    assert_decode codec arr a

let test_loop_decode (TC (_, asn, _)) _ =
  let codec = Asn.(codec ber asn) in
  for i = 1 to 1000 do
    let a = Asn.random asn in
    assert_decode codec (Asn.encode codec a) a
  done


let cases = [

  case "bool" Asn.bool [
    false, [0x01; 0x01; 0x00] ;
    true , [0x01; 0x01; 0xff]
  ];

  case
    "singleton seq"
    Asn.(sequence (single @@ required bool))
    [ true, [ 0x30; 0x03; 0x01; 0x01; 0xff; ];
      true, [ 0x30; 0x80; 0x01; 0x01; 0xff; 0x00; 0x00; ] ;
    ];

  case
    "sequence with implicits"
    Asn.(sequence3
          (required int)
          (required @@ implicit 1 bool)
          (required bool))

    [ (`I 42, false, true),
      [ 0x30; 0x09;
          0x02; 0x01; 0x2a;
          0x81; 0x01; 0x00;
          0x01; 0x01; 0xff; ] ;

      (`I 42, false, true),
      [ 0x30; 0x80;
          0x02; 0x01; 0x2a;
          0x81; 0x01; 0x00;
          0x01; 0x01; 0xff;
          0x00; 0x00; ]
    ];

  case
    "sequence with optional and explicit fields"
    Asn.(sequence3
          (required @@ implicit 1 int)
          (optional @@ explicit 2 bool)
          (optional @@ implicit 3 bool))

    [ (`I 255, Some true, Some false),
      [ 0x30; 0x0c;
          0x81; 0x02; 0x00; 0xff;
          0xa2; 0x03;
            0x01; 0x01; 0xf0;
          0x83; 0x01; 0x00; ] ;

      (`I 255, Some true, Some false),
      [ 0x30; 0x80;
          0x81; 0x02; 0x00; 0xff;
          0xa2; 0x03;
            0x01; 0x01; 0xf0;
          0x83; 0x01; 0x00;
          0x00; 0x00; ] ;

      (`I 255, Some true, Some false),
      [ 0x30; 0x80;
          0x81; 0x02; 0x00; 0xff;
          0xa2; 0x80;
            0x01; 0x01; 0xf0;
            0x00; 0x00;
          0x83; 0x01; 0x00;
          0x00; 0x00; ] ;
    ];

  case
    "sequence with missing optional and choice fields"
    Asn.(sequence3
          (required @@ choice2 bool int)
          (optional @@ choice2 bool int)
          (optional @@ explicit 0
                    @@ choice2 int (implicit 1 int)))

    [ (`C1 true, None, None),
      [ 0x30; 0x03; 0x01; 0x01; 0xff ] ;

      (`C2 (`I 42), None, None),
      [ 0x30; 0x05; 0x02; 0x03; 0x00; 0x00; 0x2a ] ;

      (`C1 false, Some (`C2 (`I 42)), None),
      [ 0x30; 0x06;
          0x01; 0x01; 0x00;
          0x02; 0x01; 0x2a ] ;

      (`C1 true, None, Some (`C1 (`I 42))),
      [ 0x30; 0x08;
          0x01; 0x01; 0xff;
          0xa0; 0x03;
            0x02; 0x01; 0x2a ] ;

      (`C2 (`I (-2)), Some (`C2 (`I 42)), Some (`C2 (`I 42))),
      [ 0x30; 0x0b;
          0x02; 0x01; 0xfe;
          0x02; 0x01; 0x2a;
          0xa0; 0x03;
            0x81; 0x01; 0x2a ] ;

      (`C2 (`I (-3)), None, Some (`C2 (`I 42))),
      [ 0x30; 0x0a;
          0x02; 0x01; 0xfd;
          0xa0; 0x80;
            0x81; 0x01; 0x2a; 0x00; 0x00; ] ;

      (`C2 (`I (-4)), None, Some (`C1 (`I 42))),
      [ 0x30; 0x80;
          0x02; 0x01; 0xfc;
          0xa0; 0x80;
            0x02; 0x01; 0x2a; 0x00; 0x00;
          0x00; 0x00 ] ;
    ];

  case
    "sequence with sequence"
    Asn.(sequence2
          (required @@
            sequence2
              (optional @@ implicit 1 bool)
              (optional bool))
          (required bool))

    [ ((Some true, Some false), true),
      [ 0x30; 0x0b ;
          0x30; 0x06;
            0x81; 0x01; 0xff;
            0x01; 0x01; 0x00;
          0x01; 0x01; 0xff ] ;

      ((None, Some false), true),
      [ 0x30; 0x08 ;
          0x30; 0x03;
            0x01; 0x01; 0x00;
          0x01; 0x01; 0xff ] ;

      ((Some true, None), true),
      [ 0x30; 0x08 ;
          0x30; 0x03;
            0x81; 0x01; 0xff;
          0x01; 0x01; 0xff ] ;

      ((Some true, None), true),
      [ 0x30; 0x80 ;
          0x30; 0x80;
            0x81; 0x01; 0xff;
            0x00; 0x00;
          0x01; 0x01; 0xff;
          0x00; 0x00 ] ;
    ];

  case
    "sequence_of choice"
    Asn.(sequence2
          (required @@
            sequence_of
              (choice2 bool (implicit 0 bool)))
          (required @@ bool))

    [ ([`C2 true; `C2 false; `C1 true], true),
      [ 0x30; 0x0e;
          0x30; 0x09;
            0x80; 0x01; 0xff;
            0x80; 0x01; 0x00;
            0x01; 0x01; 0xff;
          0x01; 0x01; 0xff ] ;

      ([`C2 true; `C2 false; `C1 true], true),
      [ 0x30; 0x80;
          0x30; 0x80;
            0x80; 0x01; 0xff;
            0x80; 0x01; 0x00;
            0x01; 0x01; 0xff;
            0x00; 0x00;
          0x01; 0x01; 0xff;
          0x00; 0x00; ]
    ];

  case
    "sets"
    Asn.(set4 (required @@ implicit 1 bool)
              (required @@ implicit 2 bool)
              (required @@ implicit 3 int )
              (optional @@ implicit 4 int ))

    [ (true, false, `I 42, None),
      [ 0x31; 0x09;
          0x81; 0x01; 0xff;
          0x82; 0x01; 0x00;
          0x83; 0x01; 0x2a; ];

      (true, false, `I 42, Some (`I (-1))),
      [ 0x31; 0x0c;
          0x82; 0x01; 0x00;
          0x84; 0x01; 0xff;
          0x81; 0x01; 0xff;
          0x83; 0x01; 0x2a; ];

      (true, false, `I 42, None),
      [ 0x31; 0x09;
          0x82; 0x01; 0x00;
          0x83; 0x01; 0x2a;
          0x81; 0x01; 0xff; ];

      (true, false, `I 42, Some (`I 15)),
      [ 0x31; 0x0c;
          0x83; 0x01; 0x2a;
          0x82; 0x01; 0x00;
          0x81; 0x01; 0xff;
          0x84; 0x01; 0x0f; ];

      (true, false, `I 42, None),
      [ 0x31; 0x80;
          0x82; 0x01; 0x00;
          0x83; 0x01; 0x2a;
          0x81; 0x01; 0xff;
          0x00; 0x00 ];

      (true, false, `I 42, Some (`I 15)),
      [ 0x31; 0x80;
          0x83; 0x01; 0x2a;
          0x82; 0x01; 0x00;
          0x81; 0x01; 0xff;
          0x84; 0x01; 0x0f;
          0x00; 0x00 ];
    ];

  case
    "set or seq"
    Asn.(choice2
          (set2 (optional int )
                (optional bool))
          (sequence2 (optional int )
                     (optional bool)))

    [ (`C1 (None, Some true)),
      [ 0x31; 0x03;
          0x01; 0x01; 0xff; ];

      (`C1 (Some (`I 42), None)),
      [ 0x31; 0x03;
          0x02; 0x01; 0x2a; ];

      (`C1 (Some (`I 42), Some true)),
      [ 0x31; 0x06;
          0x01; 0x01; 0xff;
          0x02; 0x01; 0x2a; ];

      (`C2 (None, Some true)),
      [ 0x30; 0x03;
          0x01; 0x01; 0xff; ];

      (`C2 (Some (`I 42), None)),
      [ 0x30; 0x03;
          0x02; 0x01; 0x2a; ];

      (`C2 (Some (`I 42), Some true)),
      [ 0x30; 0x06;
          0x02; 0x01; 0x2a;
          0x01; 0x01; 0xff; ];
    ];

  case
    "large tag"
    Asn.(implicit 6666666 bool)
    [ true , [ 0x9f; 0x83; 0x96; 0xf3; 0x2a; 0x01; 0xff; ];
      false, [ 0x9f; 0x83; 0x96; 0xf3; 0x2a; 0x01; 0x00; ];
    ];


  case
    "recursive encoding"
    Asn.(
      fix @@ fun list ->
        map (function `C1 () -> [] | `C2 (x, xs) -> x::xs)
            (function [] -> `C1 () | x::xs -> `C2 (x, xs))
        @@
        choice2
          null
          (sequence2
            (required bool)
            (required list)))

    [ [], [ 0x05; 0x00 ] ;

      [true],
      [ 0x30; 0x05;
              0x01; 0x01; 0xff;
              0x05; 0x00; ] ;

      [true; false; true],
      [ 0x30; 0x0f;
          0x01; 0x01; 0xff;
          0x30; 0x0a;
            0x01; 0x01; 0x00;
            0x30; 0x05;
              0x01; 0x01; 0xff;
              0x05; 0x00; ] ;

      [false; true; false],
      [ 0x30; 0x80;
          0x01; 0x01; 0x00;
          0x30; 0x80;
            0x01; 0x01; 0xff;
            0x30; 0x80;
              0x01; 0x01; 0x00;
              0x05; 0x00;
              0x00; 0x00;
            0x00; 0x00;
          0x00; 0x00; ] ;

      [false; true; false],
      [ 0x30; 0x80;
          0x01; 0x01; 0x00;
          0x30; 0x80;
            0x01; 0x01; 0xff;
            0x30; 0x80;
              0x01; 0x01; 0x00;
              0x05; 0x00;
              0x00; 0x00;
            0x00; 0x00;
          0x00; 0x00; ] ;
    ];

  case
    "ia5 string"
    Asn.ia5_string

    [ "abc", [ 0x16; 0x03; 0x61; 0x62; 0x63; ];

      "abcd",
      [ 0x36; 0x0a;
          0x16; 0x01; 0x61;
          0x16; 0x01; 0x62;
          0x16; 0x02; 0x63; 0x64; ];

      "abcd",
      [ 0x36; 0x80;
          0x16; 0x01; 0x61;
          0x16; 0x01; 0x62;
          0x16; 0x02; 0x63; 0x64;
          0x00; 0x00; ];

      "abcd",
      [ 0x36; 0x80;
          0x36; 0x06;
            0x16; 0x01; 0x61;
            0x16; 0x01; 0x62;
          0x16; 0x02; 0x63; 0x64;
          0x00; 0x00; ];

      "test1@rsa.com",
      [ 0x16; 0x0d; 0x74; 0x65; 0x73; 0x74; 0x31; 0x40; 0x72; 0x73;
        0x61; 0x2e; 0x63; 0x6f; 0x6d; ] ;

      "test1@rsa.com",
      [ 0x16; 0x81; 0x0d;
          0x74; 0x65; 0x73; 0x74; 0x31; 0x40; 0x72; 0x73; 0x61; 0x2e; 0x63; 0x6f; 0x6d ];

      "test1@rsa.com",
      [ 0x36; 0x13;
          0x16; 0x05; 0x74; 0x65; 0x73; 0x74; 0x31;
          0x16; 0x01; 0x40;
          0x16; 0x07; 0x72; 0x73; 0x61; 0x2e; 0x63; 0x6f; 0x6d; ]
    ]

]


let suite =
  "ASN.1" >::: [
    "BER decoding" >:::
      List.map
        (fun (TC (name, _, _) as tc) -> name >:: test_decode tc)
        cases ;
    "BER encode->decode" >:::
      List.map
        (fun (TC (name, _, _) as tc) -> name >:: test_loop_decode tc)
        cases
  ]

