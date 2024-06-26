import { createActor as orderActor } from "../../../declarations/order";
import { Actor, Agent } from "@dfinity/agent";
import { getIsLocal } from "./client";
import { ItemId } from './types';
import { Principal } from "@dfinity/principal";
import { ItemRef, parseItemRef } from "../data/Data";

export async function addToFolder(agent: Agent, catId: ItemRef, itemId: ItemRef, comment: boolean, side: 'beginning' | 'end') {
    const orderClient = orderActor(process.env.CANISTER_ID_ORDER, {agent});
    const side2 = side === 'beginning' ? {beginning: null} : {end: null};
    await orderClient.addItemToFolder(
        [catId.canister, BigInt(catId.id)],
        [itemId.canister, BigInt(itemId.id)],
        comment,
        side2,
    );
}

// TODO: Change `string[]` argument type
export async function addToMultipleFolders(agent: Agent, cats: [string, 'beginning' | 'end'][], itemId: ItemRef, comment: boolean) {
    for (const folder of cats) {
        await addToFolder(agent, parseItemRef(folder[0]), itemId, comment, folder[1]); // TODO: It may fail to parse.
    }
}