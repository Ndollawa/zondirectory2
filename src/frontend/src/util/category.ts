import { initializeCanDBPartitionClient, intializeCanDBIndexClient } from "./client";
import { idlFactory as CanDBPartitionIDL } from "../../../declarations/CanDBPartition/index";
import { Actor, HttpAgent } from "@dfinity/agent";

async function AddToCategory() {
    const isLocal = true; // TODO
    const host = isLocal ? "http://127.0.0.1:8000" : "https://ic0.app";
    const agent = new HttpAgent({ host });

    const canDBIndexClient = intializeCanDBIndexClient(isLocal);
    const canDBPartitionClient = initializeCanDBPartitionClient(isLocal, canDBIndexClient);

    const canistersResult = (await canDBIndexClient.indexCanisterActor.getCanistersByPK(""/* FIXME */));
    const canisterId = canistersResult[canistersResult.length - 1];
    const partition = Actor.createActor(CanDBPartitionIDL, { agent, canisterId });
    

    // TODO

    // let sybilResults = await canDBPartitionClient.query<CanDBPartition["get"]>( // FIXME
    //     "", // pk, // FIXME
    //     (actor) => actor.get({sk: "s/username"}), // FIXME
    // );
}